"""Resolve + lazily materialize a single class occurrence for check-in.

``resolve`` turns ``(class_id, gym_id, occurrence_date)`` into a
``ResolvedClass``: it loads the class, validates that the date is a real,
non-cancelled occurrence by running the canonical ``ClassesExpander`` over that
single day (so exception-applied time / instructor / duration and the gym-tz UTC
``occurred_at`` are exact), then lazily find-or-creates the ``class_history`` row
via ``ClassesMaterializer`` (idempotent + race-safe).

This is the one-way ``checkin -> classes`` dependency: the resolver imports the
pure ``ClassesExpander`` + the ``ClassesMaterializer`` + the expander row
mappings, all of which stay in the ``classes`` domain.
"""

import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from src.checkin.schema.checkin_schema import ResolvedClass
from src.checkin.service.checkin_queries import CheckinQueries
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.classes.service.classes_materializer import ClassesMaterializer
from src.core.config import settings
from src.shared.database import DirectDatabasePool


class CheckinClassResolver:
    """Resolves + materializes the ``class_history`` occurrence for a check-in.

    Args:
        db_pool: Injected database connection pool.
        expander: The canonical recurrence + exception expander (pure).
        materializer: Lazy find-or-create of the class_history occurrence.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
        materializer: ClassesMaterializer,
    ) -> None:
        self._queries = CheckinQueries(db_pool)
        self._expander = expander
        self._materializer = materializer

    async def resolve(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> ResolvedClass:
        """Resolve + materialize a single class occurrence.

        Raises:
            ValueError: If the class does not exist / is deleted / is inactive,
                the gym is missing, no real non-cancelled occurrence lands on
                ``occurrence_date``, or the occurrence starts further than
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

        gym_tz = await self._queries.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError("Gym not found")

        occurrence = await self._expand_single_day(
            class_row, class_id, occurrence_date, gym_tz
        )
        if occurrence is None:
            raise ValueError(
                f"No class occurrence on {occurrence_date} for this class"
            )

        # Check-in opens a fixed window before the class starts (2h by default,
        # so back-to-back classes can be checked in together). A check-in for an
        # occurrence further out than that is rejected before anything is
        # materialized. Past / in-session occurrences always pass.
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

        class_history_id, _ = await self._materializer.find_or_create_history(
            class_id,
            gym_id,
            occurrence.occurred_at,
            occurrence.instructor_id,
            occurrence.duration_minutes,
        )

        return ResolvedClass(
            class_history_id=class_history_id,
            class_id=class_id,
            gym_id=gym_id,
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

    async def _expand_single_day(
        self,
        class_row: dict,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> EffectiveOccurrence | None:
        """Run the expander over ``[date, date]`` and return the effective
        occurrence on that date (None when cancelled / not-a-recurrence-date).

        Loading instance + range exceptions for the single day and matching on
        ``effective_date`` gives the exception-applied time / instructor /
        duration and the gym-tz UTC ``occurred_at`` used to materialize.
        """
        instances = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        ranges = await self._queries.get_range_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        occurrences = self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            occurrence_date,
            occurrence_date,
            gym_tz,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.effective_date == occurrence_date
            ),
            None,
        )

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
