"""Frozen view service for the CRM members list."""

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
from src.shared.formatters import format_date, format_duration, format_price
from src.shared.sql_loader import load_sql


class CrmFrozenViewService(CrmBaseViewService):
    """Fetches and formats rows for the Frozen view.

    Shows frozen members sorted by days frozen ascending.
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
        """Map a database row to a FrozenViewRow.

        Args:
            row: Database result row as a mapping.
            today: Current date for computing freeze duration.

        Returns:
            FrozenViewRow with pre-formatted fields.
        """
        freeze_start = row.get("freeze_start_date")
        freeze_end = row.get("freeze_end_date")

        if freeze_start and freeze_end:
            duration_days = (freeze_end - freeze_start).days
        elif freeze_start:
            duration_days = (today - freeze_start).days
        else:
            duration_days = 0

        return FrozenViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            freeze_start=(format_date(freeze_start) if freeze_start else "N/A"),
            freeze_duration=format_duration(duration_days),
            freeze_end=(format_date(freeze_end) if freeze_end else "N/A"),
            price=format_price(
                row.get("total_price", 0),
                row.get("duration_unit", "month"),
            ),
        )
