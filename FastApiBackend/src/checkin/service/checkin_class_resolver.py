"""Resolve a single class occurrence for check-in.

``resolve`` turns ``(class_id, gym_id, occurrence_date, occurrence_time)``
into a ``ResolvedClass``: it loads the class identity, resolves the
occurrence by its ORIGINAL slot through the shared
``CheckinOccurrenceResolution`` (the one resolution algorithm sign-up also
uses, so the two can never disagree about whether an occurrence exists),
then applies the early-check-in gate. Purely a read — occurrences are always
computed, never stored, so there is no materialization step.
"""

import json
from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID

from src.checkin.checkin_exceptions import (
    CheckinClassDeletedError,
    CheckinClassInactiveError,
    CheckinClassNotFoundError,
    CheckinNotOpenYetError,
    CheckinOccurrenceNotFoundError,
)
from src.checkin.schema.checkin_schema import ResolvedClass
from src.checkin.service.checkin_occurrence_resolution import (
    CheckinOccurrenceResolution,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.core.config import settings
from src.shared.database import DirectDatabasePool


class CheckinClassResolver:
    """Resolves the occurrence for a check-in — a pure read, nothing written.

    Args:
        db_pool: Injected database connection pool.
        occurrence_resolution: The shared original-date occurrence resolver
            (the one-way ``checkin -> classes`` seam lives inside it).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        occurrence_resolution: CheckinOccurrenceResolution,
    ) -> None:
        self._queries = CheckinQueries(db_pool)
        self._occurrence_resolution = occurrence_resolution

    async def resolve(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
    ) -> ResolvedClass:
        """Resolve a single class occurrence.

        Raises:
            CheckinClassNotFoundError: The class does not exist for this gym
                (router -> 404).
            CheckinClassDeletedError: The class is soft-deleted.
            CheckinClassInactiveError: The class is paused.
            CheckinOccurrenceNotFoundError: No real non-cancelled occurrence
                lands on the exact ``(occurrence_date, occurrence_time)`` slot
                (its ORIGINAL slot).
            CheckinNotOpenYetError: The occurrence starts further than
                ``settings.checkin_opens_hours_before_start`` in the future.
        """
        class_row = await self._queries.get_class_for_checkin(
            class_id, gym_id, occurrence_date, occurrence_time
        )
        if class_row is None:
            raise CheckinClassNotFoundError("Class not found")
        if class_row["is_deleted"]:
            raise CheckinClassDeletedError("Class has been deleted")
        if not class_row["is_active"]:
            raise CheckinClassInactiveError("Class is not active")

        occurrence = await self._occurrence_resolution.resolve_original(
            class_id, occurrence_date, occurrence_time
        )
        if occurrence is None:
            raise CheckinOccurrenceNotFoundError(
                f"No class occurrence on {occurrence_date} at "
                f"{occurrence_time} for this class"
            )

        # Check-in opens a fixed window before the class starts (2h by default,
        # so back-to-back classes can be checked in together). A check-in for an
        # occurrence further out than that is rejected. Past / in-session
        # occurrences always pass.
        opens_at = datetime.now(UTC) + timedelta(
            hours=settings.checkin_opens_hours_before_start
        )
        if occurrence.occurred_at > opens_at:
            raise CheckinNotOpenYetError(
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
