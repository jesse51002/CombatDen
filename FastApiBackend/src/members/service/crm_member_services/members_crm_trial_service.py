"""Trial view service for the CRM members list."""

from datetime import date
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    MembersListFilters,
    TrialViewRow,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_date
from src.shared.sql_loader import load_sql


class CrmTrialViewService(CrmBaseViewService):
    """Fetches and formats rows for the Trial view.

    Shows trial members sorted by days remaining descending.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[TrialViewRow]:
        """Fetch Trial view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of TrialViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "crm_views" / "trial_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        today = rows[0]["gym_today"] if rows else date.today()
        return [self._map_row(r, today) for r in rows]

    def _map_row(self, row: dict, today: date) -> TrialViewRow:
        """Map a database row to a TrialViewRow.

        Args:
            row: Database result row as a mapping.
            today: Current date for computing days remaining.

        Returns:
            TrialViewRow with pre-formatted fields.
        """
        end_date = row["end_date"]
        days_remaining = (end_date - today).days if end_date else 0
        return TrialViewRow(
            member_id=row["member_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            days_remaining=days_remaining,
            start_date=format_date(row["start_date"]),
            end_date=(format_date(end_date) if end_date else "N/A"),
        )
