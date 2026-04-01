"""Promotions view service for the CRM members list."""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    MembersListFilters,
    PromotionsViewRow,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_duration_since
from src.shared.sql_loader import load_sql


class CrmPromotionsViewService(CrmBaseViewService):
    """Fetches and formats rows for the Promotions view.

    Shows all members sorted by classes remaining until
    promotion (ascending).
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[PromotionsViewRow]:
        """Fetch Promotions view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of PromotionsViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "promotions_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()
        return [self._map_row(r) for r in rows]

    def _map_row(self, row: dict) -> PromotionsViewRow:
        """Map a database row to a PromotionsViewRow.

        Args:
            row: Database result row as a mapping.

        Returns:
            PromotionsViewRow with pre-formatted fields.
        """
        rank_name = self.get_rank_name(row.get("current_rank"), row)
        estimated = self.get_estimated_classes_for_rank(row.get("current_rank"), row)
        classes_in_rank = row.get("classes_in_rank", 0)
        classes_until = max(0, estimated - classes_in_rank)

        rank_since = row.get("last_rank_change") or row.get("profile_created_at")
        time_in_rank_str = format_duration_since(rank_since)

        return PromotionsViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            rank=rank_name,
            rank_icon_url=None,
            time_in_rank=time_in_rank_str,
            classes_until_promotion=classes_until,
        )
