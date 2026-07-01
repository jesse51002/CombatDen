"""Read the combined roster (signed-up ∪ attended) of one class occurrence.

``list_attendees`` resolves the materialized ``class_history`` row for a
(class, gym, gym-local occurrence date) the same way the undo service does —
by the gym-local day's UTC bounds, so a per-occurrence time override still
resolves to the same row — for reporting purposes, then reads the combined
roster: every member who is signed up (``class_signups``) OR attended
(``member_attendance``), each flagged. A signed-up-only member's attendance
fields are NULL; the occurrence need not be materialized for sign-ups to show
(a future occurrence can carry sign-ups with no ``class_history`` row yet).

This is a read-only sibling of the check-in write path: no expander, no
materialize. It reuses ``CheckinQueries`` for the gym timezone, the
find-history-for-day lookup, and the roster join.
"""

from datetime import date
from uuid import UUID

from src.checkin.schema.checkin_schema import (
    Attendee,
    AttendeeListResponse,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_local_day_bounds_utc


class CheckinAttendeesService:
    """Lists the combined signed-up-or-attended roster of one occurrence.

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
        """Return everyone signed up or attended on ``occurrence_date``.

        Raises:
            ValueError: If the gym does not exist (mapped to 404 by the router).
        """
        gym_tz = await self._queries.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError("Gym not found")

        day_start, day_end = gym_local_day_bounds_utc(occurrence_date, gym_tz)
        history_id = await self._queries.find_history_for_day(
            class_id, gym_id, day_start, day_end
        )

        rows = await self._queries.get_roster(
            class_id, gym_id, occurrence_date, day_start, day_end
        )
        return AttendeeListResponse(
            class_id=class_id,
            occurrence_date=occurrence_date,
            class_history_id=history_id,
            attendees=[
                Attendee(
                    member_id=row["member_id"],
                    full_name=row["full_name"],
                    signed_up=row["signed_up"],
                    attended=row["attended"],
                    log_id=row["log_id"],
                    plan_id=row["plan_id"],
                    item_id=row["item_id"],
                )
                for row in rows
            ],
        )
