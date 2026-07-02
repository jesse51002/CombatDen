"""A member's class history — the member-page history card's data source.

Two reads in one session: the member's OPEN reservations (soonest first,
unpaginated) and their paginated HISTORY — attended occurrences plus
no-shows (a reservation whose occurrence ended with no matching attendance
on the exact original slot). Classification lives in the SQL
(``checkin_member_upcoming.sql`` / ``checkin_member_history.sql``); this
service just pages and maps rows.
"""

from uuid import UUID

from src.checkin import SQL_DIR
from src.checkin.schema.checkin_history_schema import (
    MemberClassHistoryResponse,
    MemberClassHistoryRow,
    MemberClassHistoryStatus,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_rows import fetch_all
from src.shared.sql_loader import load_sql


class CheckinHistoryService:
    """Loads one member's class history (reservations + attendance + no-shows).

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_history(
        self,
        member_id: UUID,
        gym_id: UUID,
        limit: int,
        offset: int,
    ) -> MemberClassHistoryResponse:
        """The member's upcoming reservations + a page of their history.

        Args:
            member_id: The member.
            gym_id: The gym scope.
            limit: History page size (SQL LIMIT).
            offset: History page offset (SQL OFFSET).

        Returns:
            The card feed: unpaginated ``upcoming`` (every open
            reservation), one ``history`` page newest-first, and
            ``has_more`` for the CRM's "Show more".
        """
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }
        async with self._db_pool.session() as session:
            upcoming_rows = await fetch_all(
                session,
                load_sql(SQL_DIR / "checkin_member_upcoming.sql"),
                params,
            )
            history_rows = await fetch_all(
                session,
                load_sql(SQL_DIR / "checkin_member_history.sql"),
                {**params, "limit": limit, "offset": offset},
            )

        total = (
            int(history_rows[0]["total_rows"]) if history_rows else 0
        )
        return MemberClassHistoryResponse(
            upcoming=[
                self._row(row, MemberClassHistoryStatus.reserved)
                for row in upcoming_rows
            ],
            history=[
                self._row(row, MemberClassHistoryStatus(row["status"]))
                for row in history_rows
            ],
            has_more=offset + len(history_rows) < total,
        )

    @staticmethod
    def _row(
        row: dict, status: MemberClassHistoryStatus
    ) -> MemberClassHistoryRow:
        return MemberClassHistoryRow(
            class_id=row["class_id"],
            class_name=row["class_name"],
            image_url=row["image_url"],
            original_date=row["original_date"],
            original_time=row["original_time"],
            duration_minutes=row["duration_minutes"],
            occurred_at=row["occurred_at"],
            status=status,
        )
