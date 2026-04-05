"""All view service for the CRM members list."""

from collections import defaultdict
from datetime import UTC, date, datetime
from uuid import UUID

from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.members import SQL_DIR
from src.members.schema.members_crm_members_list_schema import (
    AllViewRow,
    CrmMemberStatus,
    MembersListFilters,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
)
from src.shared.formatters import format_price
from src.shared.sql_loader import load_sql

PRIORITY_LOWEST = 99


class CrmAllViewService(CrmBaseViewService):
    """Fetches and formats rows for the All view.

    Deduplicates members with multiple memberships by
    selecting the highest-priority status per member.
    """

    async def fetch(
        self,
        session: AsyncSession,
        gym_id: UUID,
        filters: MembersListFilters,
        start_index: int,
        count: int,
    ) -> list[AllViewRow]:
        """Fetch All view rows, deduplicate, and paginate.

        Args:
            session: Active database session.
            gym_id: The gym to list members for.
            filters: Active filters to apply.
            start_index: Pagination offset.
            count: Number of rows per page.

        Returns:
            List of AllViewRow with one entry per member.
        """
        where, params = self.build_where_clause(gym_id, filters)
        sql = load_sql(
            SQL_DIR / "all_view.sql",
            {"where_clause": where},
        )
        query = text(sql)

        result = await session.execute(query, params)
        rows = result.mappings().all()

        deduped = self._deduplicate(rows)
        page = deduped[start_index : start_index + count]
        return [self._map_row(r) for r in page]

    def _deduplicate(
        self,
        rows: list[dict],
    ) -> list[dict]:
        """Group rows by member and keep the highest-priority.

        Priority (lowest number wins):
            1. overdue (next_due_date < today, not cancelled)
            2. active paid (status=active, plan_type != trial)
            3. trial (plan_type=trial, status=active)
            4. frozen
            5. ended
            6. no membership (NULL membership fields)

        Args:
            rows: Raw database rows (may have dupes).

        Returns:
            Deduplicated rows sorted by original query order.
        """
        today = date.today()
        grouped: dict[UUID, list[tuple[int, int, dict]]] = defaultdict(list)

        for idx, row in enumerate(rows):
            priority = self._score_priority(row, today)
            grouped[row["crm_user_id"]].append((priority, idx, row))

        winners = []
        for members in grouped.values():
            members.sort(key=lambda t: (t[0], t[1]))
            _, original_idx, best_row = members[0]
            winners.append((original_idx, best_row))

        winners.sort(key=lambda t: t[0])
        return [row for _, row in winners]

    def _score_priority(self, row: dict, today: date) -> int:
        """Score a row's priority for deduplication.

        Args:
            row: Database result row as a mapping.
            today: Current date for overdue check.

        Returns:
            Integer priority (lower = higher priority).
        """
        status = row.get("status")
        plan_type = row.get("plan_type")
        next_due = row.get("next_due_date")

        if status is None:
            return PRIORITY_LOWEST

        if status != CrmMemberStatus.cancelled and next_due and next_due < today:
            return 1

        if status == CrmMemberStatus.active and plan_type != PlanType.trial:
            return 2

        if plan_type == PlanType.trial and status == CrmMemberStatus.active:
            return 3

        if status == CrmMemberStatus.frozen:
            return 4

        if status == CrmMemberStatus.ended:
            return 5

        return PRIORITY_LOWEST + 1

    def _map_row(self, row: dict) -> AllViewRow:
        """Map a database row to an AllViewRow.

        Args:
            row: Database result row as a mapping.

        Returns:
            AllViewRow with pre-formatted display strings.
        """
        if row.get("status") is None:
            return AllViewRow(
                crm_user_id=row["crm_user_id"],
                name=f"{row['first_name']} {row['last_name']}",
                avatar_url=row.get("photo_url"),
                email=row.get("email"),
                membership_status=CrmMemberStatus.no_membership,
                membership_text="No Membership",
                days_since_last_class=self._days_since_last_class(row),
            )

        today = date.today()
        status = CrmMemberStatus(row["status"])
        next_due = row.get("next_due_date")

        if status != CrmMemberStatus.cancelled and next_due and next_due < today:
            status = CrmMemberStatus.overdue
        elif row.get("plan_type") == PlanType.trial:
            status = CrmMemberStatus.trial

        membership_text = self._build_membership_text(row)

        return AllViewRow(
            crm_user_id=row["crm_user_id"],
            name=f"{row['first_name']} {row['last_name']}",
            avatar_url=row.get("photo_url"),
            email=row.get("email"),
            membership_status=status,
            membership_text=membership_text,
            days_since_last_class=self._days_since_last_class(row),
        )

    def _days_since_last_class(self, row: dict) -> int | None:
        """Compute days since the member's last class.

        Args:
            row: Database result row.

        Returns:
            Number of days or None if no last_class.
        """
        last_class_dt = row.get("last_class")
        if not last_class_dt:
            return None
        delta = datetime.now(UTC) - last_class_dt
        return delta.days

    def _build_membership_text(self, row: dict) -> str:
        """Build the membership badge display text.

        Produces strings like:
        - "Trial (Until 1/23/2025)"
        - "Paid on 1/18/2025)"
        - "Overdue since 1/18/2025"
        - "Frozen (Until 1/28/2025)"
        - "Cancelled (On 1/18/2025)"

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
        end = row.get("end_date")
        today = date.today()

        if status == CrmMemberStatus.cancelled:
            cancel = row.get("cancel_date")
            if cancel:
                return f"Cancelled (On {cancel.month}/{cancel.day}/{cancel.year})"
            return "Cancelled"

        if next_due and next_due < today:
            if last_paid:
                return f"Overdue since {last_paid.month}/{last_paid.day}/{last_paid.year}"
            return f"Overdue ({price_str})"

        if plan_type == PlanType.trial:
            end_str = f"{end.month}/{end.day}/{end.year}" if end else ""

            if status == CrmMemberStatus.ended:
                return f"Trial ended {end_str}"
            elif status == CrmMemberStatus.frozen:
                freeze_end = row.get("freeze_end_date")
                if freeze_end:
                    return f"Trial Frozen (Until {freeze_end.month}/{freeze_end.day}/{freeze_end.year})"  # noqa: E501
                return "Trial frozen"

            return f"Trial until {end_str}"

        if status == CrmMemberStatus.ended:
            if end:
                return f"Ended (On {end.month}/{end.day}/{end.year})"
            return "Ended"

        if status == CrmMemberStatus.frozen:
            freeze_end = row.get("freeze_end_date")
            if freeze_end:
                return f"Frozen (Until {freeze_end.month}/{freeze_end.day}/{freeze_end.year})"
            return "Frozen"

        if last_paid:
            return f"Paid on {last_paid.month}/{last_paid.day}/{last_paid.year})"

        return f"Active ({price_str})"
