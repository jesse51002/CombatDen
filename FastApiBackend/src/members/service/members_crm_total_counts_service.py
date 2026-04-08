"""Service for fetching CRM member total counts."""

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    MembersListTotalCounts,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class CrmTotalCountsService:
    """Fetches unfiltered member counts per status.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_total_counts(
        self,
        gym_id: UUID,
    ) -> MembersListTotalCounts:
        """Fetch unfiltered total counts for the subtitle.

        Args:
            gym_id: The gym to count members for.

        Returns:
            MembersListTotalCounts with active, trial,
            frozen, overdue.
        """
        sql = load_sql(SQL_DIR / "crm_views" / "total_counts.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), {"gym_id": str(gym_id)})
            row = result.mappings().one()

        return MembersListTotalCounts(
            active=row["active"],
            trial=row["trial"],
            frozen=row["frozen"],
            overdue=row["overdue"],
        )
