"""The ONE occurrence-resolution algorithm the checkin domain shares.

``resolve_original`` turns ``(class_id, occurrence_date, occurrence_time)``
into the ``EffectiveOccurrence`` whose ORIGINAL slot is exactly
``(occurrence_date, occurrence_time)`` — the identity every checkin API call
addresses — by loading the class's schedule versions + exceptions and
expanding through the pure ``ClassesVersionExpander`` (the one-way
``checkin -> classes`` dependency). A class may occur several times on one
day (``weekday_slots`` holds a slot list per day), so the date ALONE never
identifies an occurrence — the time is required and the match is EXACT
(``original_date == occurrence_date and original_time == occurrence_time``),
never a first-match pick off the day's slots.

Why a naive single-day expand isn't enough: an occurrence is addressed by
its ORIGINAL slot, never its effective (post-reschedule) slot — see the
class-system-guide skill. Expanding a bare window of exactly
``[occurrence_date, occurrence_date]`` would silently miss an occurrence
that's been rescheduled to a DIFFERENT date: the inner ``ClassesExpander``
drops a reschedule instance exception whose ``new_date`` falls outside the
expand window (it filters on the EFFECTIVE date landing in-window).
``_resolution_window`` widens the window to also cover the exception's
``new_date`` when one exists (and the occurrence isn't cancelled) before
expanding once and filtering by the exact original slot — the same problem
``ClassesUndoService`` (the classes-domain reschedule engine) solves with a
separate ownership + raw-exception-row lookup.

Both occurrence-addressed services — ``CheckinClassResolver`` (check-in) and
``SignupService`` (reservations) — inject THIS service, so check-in and
sign-up can never disagree about whether an occurrence exists. It is a
shared concern service, not a facade: each caller still owns its own
validation/gating on the resolved occurrence.
"""

from datetime import date, time
from uuid import UUID

from src.checkin.service.checkin_queries import CheckinQueries
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.service.classes_expander_mapping import (
    to_expander_instance,
    to_expander_range,
    to_expander_schedule,
)
from src.classes.service.classes_version_expander import ClassesVersionExpander
from src.shared.database import DirectDatabasePool


class CheckinOccurrenceResolution:
    """Resolves an occurrence by its ORIGINAL date — a pure read.

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

    async def resolve_original(
        self,
        class_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
        include_cancelled: bool = False,
    ) -> EffectiveOccurrence | None:
        """The occurrence whose ORIGINAL slot is exactly ``(occurrence_date,
        occurrence_time)``, or None when the class has never been scheduled,
        the slot isn't a recurrence slot, or (with the default
        ``include_cancelled=False``) it's cancelled that day.
        ``include_cancelled=True`` emits a cancelled occurrence flagged
        instead — the sign-up path uses it to distinguish "cancelled that
        day" from "never a recurrence slot" in its errors.
        """
        versions = await self._queries.get_schedule_versions(class_id)
        if not versions:
            return None

        window_start, window_end = await self._resolution_window(
            class_id, occurrence_date, occurrence_time
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
            include_cancelled=include_cancelled,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.original_date == occurrence_date
                and occ.original_time == occurrence_time
            ),
            None,
        )

    async def _resolution_window(
        self, class_id: UUID, occurrence_date: date, occurrence_time: time
    ) -> tuple[date, date]:
        """The window to expand: normally just ``occurrence_date``, widened
        to also cover a reschedule's ``new_date`` so the moved occurrence
        still resolves when addressed by its ORIGINAL slot. Several
        exceptions may share ``occurrence_date`` (one per slot), so the
        exact-slot match on ``original_time`` picks THIS slot's exception —
        never the day's first one."""
        same_day = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        exception = next(
            (
                exc
                for exc in same_day
                if exc["original_time"] == occurrence_time
            ),
            None,
        )
        if (
            exception is None
            or exception["is_cancelled"]
            or exception["new_date"] is None
        ):
            return occurrence_date, occurrence_date
        new_date = exception["new_date"]
        return min(occurrence_date, new_date), max(occurrence_date, new_date)
