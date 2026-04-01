"""All view service for the CRM members list."""

from datetime import UTC, date, datetime
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    AllViewRow,
    MembershipStatus,
    MembersListFilters,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_price
from src.shared.sql_loader import load_sql


class CrmAllViewService(CrmBaseViewService):
    """Fetches and formats rows for the All view.

    Sorted by status priority (trial, active, frozen, cancelled),
    then by date joined ascending.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[AllViewRow]:
        """Fetch All view rows from the database.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of AllViewRow with pre-formatted fields.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "all_view.sql",
            {"where_clause": where},
        )
        params["limit"] = count
        params["offset"] = start_index
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()
        return [self._map_row(r) for r in rows]

    def _map_row(self, row: dict) -> AllViewRow:
        """Map a database row to an AllViewRow.

        Args:
            row: Database result row as a mapping.

        Returns:
            AllViewRow with pre-formatted display strings.
        """
        rank_name = self.get_rank_name(row.get("current_rank"), row)
        membership_text = self._build_membership_text(row)
        last_class_dt = row.get("last_class")
        days_since = None

        if last_class_dt:
            delta = datetime.now(UTC) - last_class_dt
            days_since = delta.days

        status = row["status"]
        if row.get("plan_type") == MembershipStatus.trial:
            status = MembershipStatus.trial.value

        return AllViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            email=row.get("email"),
            membership_status=status,
            membership_text=membership_text,
            rank=rank_name,
            rank_icon_url=None,
            days_since_last_class=days_since,
        )

    def _build_membership_text(self, row: dict) -> str:
        """Build the membership badge display text.

        Produces strings like:
        - "Trial (Until 1/23)"
        - "Paid on 1/18 ($165/month)"
        - "Missed on 1/18 ($165/month)"
        - "Frozen (Until 1/28)"
        - "Cancelled (On 1/18)"

        Args:
            row: Database row with status, plan_type,
                last_paid_date, total_price, etc.

        Returns:
            Pre-formatted membership badge string.
        """
        status = row["status"]
        plan_type = row.get("plan_type")
        price = row.get("total_price", 0)
        duration_unit = row.get("duration_unit", "month")
        price_str = format_price(price, duration_unit)

        last_paid = row.get("last_paid_date")
        next_due = row.get("next_due_date")
        today = date.today()

        if next_due and next_due < today:
            if last_paid:
                return f"Missed on {last_paid.month}/{last_paid.day} ({price_str})"
            return f"Missed ({price_str})"

        if plan_type == MembershipStatus.trial:
            end = row.get("end_date")
            if end:
                return f"Trial (Until {end.month}/{end.day})"
            return "Trial"

        if status == MembershipStatus.frozen:
            freeze_end = row.get("freeze_end_date")
            if freeze_end:
                return f"Frozen (Until {freeze_end.month}/{freeze_end.day})"
            return "Frozen"

        if status == MembershipStatus.cancelled:
            end = row.get("end_date")
            if end:
                return f"Cancelled (On {end.month}/{end.day})"
            return "Cancelled"

        if last_paid:
            return f"Paid on {last_paid.month}/{last_paid.day} ({price_str})"

        return f"Active ({price_str})"
