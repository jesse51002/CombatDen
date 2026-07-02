"""Read the combined roster (signed-up ∪ attended) of one class occurrence.

``list_attendees`` reads the combined roster of one occurrence — every member
who is signed up (``class_signups``) OR attended (``member_attendance``),
each flagged — keyed directly by the occurrence's identity
(``class_id``, ``original_date``). A signed-up-only member's attendance
fields are NULL; the occurrence doesn't need any attendance for sign-ups to
show (a future occurrence can carry sign-ups with no check-ins yet).

This is a read-only sibling of the check-in write path: no expander, no
occurrence resolution. It reuses ``CheckinQueries`` for the roster join.
"""

from datetime import date, time
from uuid import UUID

from src.checkin.schema.checkin_schema import (
    Attendee,
    AttendeeListResponse,
)
from src.checkin.service.checkin_queries import CheckinQueries
from src.shared.database import DirectDatabasePool


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
        occurrence_time: time,
    ) -> AttendeeListResponse:
        """Return everyone signed up or attended on the exact
        ``(occurrence_date, occurrence_time)`` slot (the occurrence's full
        ORIGINAL identity)."""
        rows = await self._queries.get_roster(
            class_id, gym_id, occurrence_date, occurrence_time
        )
        return AttendeeListResponse(
            class_id=class_id,
            occurrence_date=occurrence_date,
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
