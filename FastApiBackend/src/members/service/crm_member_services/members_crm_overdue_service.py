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

    Shows members with overdue payments, aggregating
    multiple overdue memberships per member.
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
            SQL_DIR / "crm_views" / "overdue_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        today = rows[0]["gym_today"] if rows else date.today()
        return [self._map_row(r, today) for r in rows]

    def _map_row(self, row: dict, today: date) -> OverdueViewRow:
        """Map an aggregated database row to an OverdueViewRow.

        Args:
            row: Database result row with aggregated fields.
            today: Current date for computing days late.

        Returns:
            OverdueViewRow with pre-formatted fields.
        """
        next_due = row["next_due_date"]
        days_late = (today - next_due).days if next_due else 0
        membership_text = self._build_membership_text(row)

        return OverdueViewRow(
            member_id=row["member_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            email=row.get("email"),
            phone=row.get("phone"),
            membership_text=membership_text,
            days_late=max(0, days_late),
        )

    def _build_membership_text(self, row: dict) -> str:
        """Build comma-separated membership display text.

        Combines all overdue plan names with their prices
        into a single string.

        Args:
            row: Database row with aggregated plan/price arrays.

        Returns:
            String like 'Gold ($165/month), Silver ($80/month)'.
        """
        plan_names = row.get("plan_names", [])
        prices = row.get("prices", [])
        duration_units = row.get("duration_units", [])

        parts = []
        for name, price, unit in zip(plan_names, prices, duration_units, strict=False):
            price_str = format_price(price, unit)
            parts.append(f"{name} ({price_str})")

        return ", ".join(parts) if parts else "Overdue"
