"""Overdue view service for the CRM members list."""

from datetime import date
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    MembersListFilters,
    OverdueViewRow,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_price
from src.shared.sql_loader import load_sql


class CrmOverdueViewService(CrmBaseViewService):
    """Fetches and formats rows for the Overdue view.

    Shows members with overdue payments, sorted by most
    days late first.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[OverdueViewRow]:
        """Fetch Overdue view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of OverdueViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "overdue_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        today = date.today()
        return [self._map_row(r, today) for r in rows]

    def _map_row(self, row: dict, today: date) -> OverdueViewRow:
        """Map a database row to an OverdueViewRow.

        Args:
            row: Database result row as a mapping.
            today: Current date for computing days late.

        Returns:
            OverdueViewRow with pre-formatted fields.
        """
        next_due = row["next_due_date"]
        days_late = (today - next_due).days if next_due else 0
        membership_text = self._build_membership_text(row)

        return OverdueViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            email=row.get("email"),
            phone=row.get("phone"),
            membership_text=membership_text,
            days_late=max(0, days_late),
        )

    def _build_membership_text(self, row: dict) -> str:
        """Build membership type display text.

        Args:
            row: Database row with plan and price info.

        Returns:
            String like 'Recurring ($165/month)'.
        """
        plan_name = row.get("plan_name", "")
        price = row.get("total_price", 0)
        duration_unit = row.get("duration_unit", "month")
        price_str = format_price(price, duration_unit)
        return f"{plan_name} ({price_str})"
