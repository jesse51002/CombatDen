"""Resolve a single class occurrence for check-in.

``resolve`` turns ``(class_id, gym_id, occurrence_date)`` into a
``ResolvedClass``: it loads the class identity, resolves the occurrence
against the class's schedule versions + exceptions via the injected
``ClassesVersionExpander``, then applies the early-check-in gate. Purely a
read — occurrences are always computed, never stored, so there is no
materialization step.

This is the one-way ``checkin -> classes`` dependency: the resolver imports
the pure ``ClassesVersionExpander`` + the expander row mappings, both of
which stay in the ``classes`` domain.

Occurrence resolution note (why a naive single-day expand isn't enough): an
occurrence is addressed by its ORIGINAL date, never its effective
(post-reschedule) date — see the class-system-guide skill. Expanding a bare
window of exactly ``[occurrence_date, occurrence_date]`` would silently miss
an occurrence that's been rescheduled to a DIFFERENT date: the inner
``ClassesExpander`` drops a reschedule instance exception whose
``new_date`` falls outside the expand window (it filters on the EFFECTIVE
date landing in-window). ``_resolution_window`` widens the window to also
cover the exception's ``new_date`` when one exists (and the occurrence isn't
cancelled) before expanding once and filtering by ``original_date`` — the
same problem ``ClassesUndoService`` (the classes-domain reschedule engine)
solves with a separate ownership + raw-exception-row lookup; this is a
functionally equivalent, single-query-shape alternative reusing the same
``ClassesVersionExpander.expand`` call every other resolution path already
uses. ``SignupService`` duplicates this same resolution (see its module
docstring) — the checkin domain deliberately has no facade, so each
occurrence-addressed caller resolves its own way.
"""

import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from src.checkin.schema.checkin_schema import ResolvedClass
from src.checkin.service.checkin_queries import CheckinQueries
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander_mapping import (
    to_expander_instance,
    to_expander_range,
    to_expander_schedule,
)
from src.classes.service.classes_version_expander import ClassesVersionExpander
from src.core.config import settings
from src.shared.database import DirectDatabasePool


class CheckinClassResolver:
    """Resolves the occurrence for a check-in — a pure read, nothing written.

    Args:
        db_pool: Injected database connection pool.
        version_expander: The versioned recurrence + exception engine (pure).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        version_expander: ClassesVersionExpander,
    ) -> None:
        self._queries = CheckinQueries(db_pool)
        self._version_expander = version_expander

    async def resolve(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> ResolvedClass:
        """Resolve a single class occurrence.

        Raises:
            ValueError: If the class does not exist / is deleted / is
                inactive, no real non-cancelled occurrence lands on
                ``occurrence_date`` (its ORIGINAL date), or the occurrence
                starts further than
                ``settings.checkin_opens_hours_before_start`` in the future
                (check-in isn't open yet).
        """
        class_row = await self._queries.get_class_for_checkin(
            class_id, gym_id, occurrence_date
        )
        if class_row is None:
            raise ValueError("Class not found")
        if class_row["is_deleted"]:
            raise ValueError("Class has been deleted")
        if not class_row["is_active"]:
            raise ValueError("Class is not active")

        occurrence = await self._resolve_occurrence(class_id, occurrence_date)
        if occurrence is None:
            raise ValueError(
                f"No class occurrence on {occurrence_date} for this class"
            )

        # Check-in opens a fixed window before the class starts (2h by default,
        # so back-to-back classes can be checked in together). A check-in for an
        # occurrence further out than that is rejected. Past / in-session
        # occurrences always pass.
        opens_at = datetime.now(UTC) + timedelta(
            hours=settings.checkin_opens_hours_before_start
        )
        if occurrence.occurred_at > opens_at:
            raise ValueError(
                "Check-in is not open yet — it opens "
                f"{settings.checkin_opens_hours_before_start} hours before the "
                "class starts"
            )

        effective_capacity = (
            class_row["exception_max_capacity"]
            if class_row["exception_max_capacity"] is not None
            else class_row["max_capacity"]
        )

        return ResolvedClass(
            class_id=class_id,
            gym_id=gym_id,
            occurrence_date=occurrence_date,
            original_time=occurrence.original_time,
            occurred_at=occurrence.occurred_at,
            points_worth=class_row["points_worth"],
            class_name=class_row["class_name"],
            max_capacity=effective_capacity,
            allowed_plan_ids=self._parse_allowed_plan_ids(
                class_row["allowed_plan_ids"]
            ),
            instructor_id=occurrence.instructor_id,
            duration_minutes=occurrence.duration_minutes,
        )

    # -- occurrence resolution --------------------------------------------

    async def _resolve_occurrence(
        self,
        class_id: UUID,
        occurrence_date: date,
    ) -> EffectiveOccurrence | None:
        """The occurrence whose ORIGINAL date is ``occurrence_date``, or None
        when the class has never been scheduled, the date isn't a
        recurrence date, or it's cancelled that day. See the module
        docstring for why the expand window is widened."""
        versions = await self._queries.get_schedule_versions(class_id)
        if not versions:
            return None

        window_start, window_end = await self._resolution_window(
            class_id, occurrence_date
        )
        instances = await self._queries.get_instance_exceptions(
            class_id, window_start, window_end
        )
        ranges = await self._queries.get_range_exceptions(
            class_id, window_start, window_end
        )
        occurrences = self._version_expander.expand(
            [to_expander_schedule(row) for row in versions],
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            window_start,
            window_end,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.original_date == occurrence_date
            ),
            None,
        )

    async def _resolution_window(
        self, class_id: UUID, occurrence_date: date
    ) -> tuple[date, date]:
        """The window to expand: normally just ``occurrence_date``, widened
        to also cover a reschedule's ``new_date`` so the moved occurrence
        still resolves when addressed by its ORIGINAL date."""
        same_day = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        exception = same_day[0] if same_day else None
        if (
            exception is None
            or exception["is_cancelled"]
            or exception["new_date"] is None
        ):
            return occurrence_date, occurrence_date
        new_date = exception["new_date"]
        return min(occurrence_date, new_date), max(occurrence_date, new_date)

    @staticmethod
    def _parse_allowed_plan_ids(raw: object) -> list[UUID] | None:
        """Coerce the JSONB allowed_plan_ids column to a UUID list.

        asyncpg may hand back JSONB as either a decoded list or a JSON string,
        so both are handled. None (the class allows every plan) stays None.
        """
        if raw is None:
            return None
        if isinstance(raw, str):
            raw = json.loads(raw)
        return [UUID(str(plan_id)) for plan_id in raw]
