"""Service for fetching CRM member total counts."""

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    MembersListTotalCounts,
)
from src.members.service.members_status_mapping import (
    load_member_dormant_sql,
    load_member_incomplete_sql,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

# The dormant tally counts members straight off the members table, so it
# correlates the shared predicate to that scan's own alias.
DORMANT_COUNT_SQL = load_member_dormant_sql(
    "dormant_m.member_id",
    "dormant_m.gym_id",
)
# Same for the incomplete tally — its own scan alias, the same shared text
# the Incomplete tab lists with.
INCOMPLETE_COUNT_SQL = load_member_incomplete_sql(
    "incomplete_m.member_id",
    "incomplete_m.gym_id",
)


class CrmTotalCountsService:
    """Fetches unfiltered member counts per status.

    Args:
        db_pool: Injected database connection pool.
        dormancy_days: How long without activity makes a short-plan
            member dormant (``settings.member_dormancy_days``).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        dormancy_days: int,
    ) -> None:
        self._db_pool = db_pool
        self._dormancy_days = dormancy_days

    async def get_total_counts(
        self,
        gym_id: UUID,
    ) -> MembersListTotalCounts:
        """Fetch unfiltered total counts for the subtitle.

        Args:
            gym_id: The gym to count members for.

        Returns:
            MembersListTotalCounts with active, trial,
            frozen, overdue, dormant, incomplete.
        """
        sql = load_sql(
            SQL_DIR / "crm_views" / "total_counts.sql",
            {
                "is_dormant": DORMANT_COUNT_SQL,
                "is_incomplete": INCOMPLETE_COUNT_SQL,
            },
        )
        params = {
            "gym_id": str(gym_id),
            "dormancy_days": self._dormancy_days,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().one()

        return MembersListTotalCounts(
            active=row["active"],
            trial=row["trial"],
            frozen=row["frozen"],
            overdue=row["overdue"],
            dormant=row["dormant"],
            incomplete=row["incomplete"],
        )
