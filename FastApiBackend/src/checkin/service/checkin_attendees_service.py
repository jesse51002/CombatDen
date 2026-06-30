"""Read the members who attended one class occurrence.

``list_attendees`` resolves the materialized ``class_history`` row for a
(class, gym, gym-local occurrence date) the same way the undo service does —
by the gym-local day's UTC bounds, so a per-occurrence time override still
resolves to the same row — then joins ``member_attendance`` to ``members``.
When the occurrence was never materialized (no check-ins yet) the attendee list
is empty.

This is a read-only sibling of the check-in write path: no expander, no
materialize. It reuses ``CheckinQueries`` for the gym timezone, the
find-history-for-day lookup, and the attendees join.
"""

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from src.checkin.schema.checkin_schema import (
    Attendee,
    AttendeeListResponse,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.shared.database import DirectDatabasePool


class CheckinAttendeesService:
    """Lists the attendees of a single class occurrence.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._queries = CheckinQueries(db_pool)

    async def list_attendees(
        self,
        gym_id: UUID,
        class_id: UUID,
        occurrence_date: date,
    ) -> AttendeeListResponse:
        """Return the members who attended the occurrence on ``occurrence_date``.

        Raises:
            ValueError: If the gym does not exist (mapped to 404 by the router).
        """
        gym_tz = await self._queries.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError("Gym not found")

        day_start, day_end = self._day_bounds_utc(occurrence_date, gym_tz)
        history_id = await self._queries.find_history_for_day(
            class_id, gym_id, day_start, day_end
        )
        if history_id is None:
            return AttendeeListResponse(
                class_id=class_id,
                occurrence_date=occurrence_date,
                class_history_id=None,
                attendees=[],
            )

        rows = await self._queries.get_attendees(history_id, gym_id)
        return AttendeeListResponse(
            class_id=class_id,
            occurrence_date=occurrence_date,
            class_history_id=history_id,
            attendees=[
                Attendee(
                    member_id=row["member_id"],
                    full_name=row["full_name"],
                    log_id=row["log_id"],
                    plan_id=row["plan_id"],
                    item_id=row["item_id"],
                )
                for row in rows
            ],
        )

    @staticmethod
    def _day_bounds_utc(
        occurrence_date: date,
        gym_tz: str,
    ) -> tuple[datetime, datetime]:
        """The gym-local day [00:00, next-00:00) converted to UTC bounds."""
        zone = ZoneInfo(gym_tz)
        day_start = datetime.combine(
            occurrence_date, time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        day_end = datetime.combine(
            occurrence_date + timedelta(days=1), time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        return day_start, day_end
