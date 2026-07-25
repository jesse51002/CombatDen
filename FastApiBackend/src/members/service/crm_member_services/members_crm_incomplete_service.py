"""Incomplete view service for the CRM members list."""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    IncompleteViewRow,
    MembersListFilters,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.members.service.members_status_mapping import (
    load_member_incomplete_sql,
)
from src.shared.sql_loader import load_sql

# Every view aliases members as `p`, so the shared incomplete predicate is
# correlated to the same two id expressions the sibling views use.
INCOMPLETE_SQL = load_member_incomplete_sql("p.member_id", "p.gym_id")


class CrmIncompleteViewService(CrmBaseViewService):
    """Fetches and formats rows for the Incomplete view.

    Lists signups that stalled: a VALID member row (one with a
    ``stripe_customer_id``) holding no membership of their own, who is
    also not the payer on anyone else's, and who holds no
    billed-but-unconfirmed non-recurring row. Newest first — the freshest
    unfinished signup is the one staff can still convert.
    ``sql/crm_views/_member_incomplete.sql`` owns the rule and the
    reasoning behind each exclusion.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[IncompleteViewRow]:
        """Fetch Incomplete view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of IncompleteViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "crm_views" / "incomplete_view.sql",
            {"where_clause": where, "is_incomplete": INCOMPLETE_SQL},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        return [self._map_row(r) for r in rows]

    def _map_row(self, row: dict) -> IncompleteViewRow:
        """Map a database row to an IncompleteViewRow.

        ``days_waiting`` is computed gym-locally in SQL (see
        incomplete_view.sql) and never re-derived here, for the same
        reason ``days_since_last_class`` is not: a bare UTC instant diff
        goes negative for an evening signup at a gym west of UTC.

        Args:
            row: Database result row as a mapping.

        Returns:
            IncompleteViewRow with pre-formatted fields.
        """
        return IncompleteViewRow(
            member_id=row["member_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            email=row.get("email"),
            phone=row.get("phone"),
            days_waiting=row["days_waiting"],
        )
