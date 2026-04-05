"""Frozen view service for the CRM members list."""

import logging
from datetime import date
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    FrozenViewRow,
    MembersListFilters,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_date, format_price
from src.shared.sql_loader import load_sql

MONTHLY_MULTIPLIERS = {
    "week": 52 / 12,
    "month": 1,
    "year": 1 / 12,
}

logger = logging.getLogger(__name__)


class CrmFrozenViewService(CrmBaseViewService):
    """Fetches and formats rows for the Frozen view.

    Shows frozen members sorted by days until unfrozen.
    Aggregates multiple frozen memberships per member.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[FrozenViewRow]:
        """Fetch Frozen view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of FrozenViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "frozen_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        today = date.today()
        return [self._map_row(r, today) for r in rows]

    def _map_row(self, row: dict, today: date) -> FrozenViewRow:
        """Map an aggregated database row to a FrozenViewRow.

        Args:
            row: Database result row with aggregated fields.
            today: Current date for computing days until unfrozen.

        Returns:
            FrozenViewRow with pre-formatted fields.
        """
        earliest_end = row.get("earliest_freeze_end")
        days_until_unfrozen = (earliest_end - today).days if earliest_end else 0

        monthly_total = self._normalize_prices_to_monthly(
            row.get("prices", []),
            row.get("duration_units", []),
        )

        return FrozenViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            freeze_start=(
                format_date(row.get("freeze_start_date"))
                if row.get("freeze_start_date")
                else "N/A"
            ),
            days_until_unfrozen=days_until_unfrozen,
            freeze_end=(
                format_date(row.get("freeze_end_date")) if row.get("freeze_end_date") else "N/A"
            ),
            price=format_price(monthly_total, "month"),
        )

    def _normalize_prices_to_monthly(
        self,
        prices: list[float],
        duration_units: list[str],
    ) -> float:
        """Normalize and sum prices to a monthly equivalent.

        Converts weekly prices (x 52/12) and yearly prices
        (/ 12) to monthly, then sums them.

        Args:
            prices: List of raw prices from ARRAY_AGG.
            duration_units: Matching duration units.

        Returns:
            Total monthly price.
        """
        total = 0.0
        for price, unit in zip(prices, duration_units, strict=False):
            if unit in MONTHLY_MULTIPLIERS:
                multiplier = MONTHLY_MULTIPLIERS[unit]
            else:
                multiplier = 1
                logger.warning(f"Duration unit isnt in dictionary {unit}")
            total += price * multiplier
        return round(total, 2)
