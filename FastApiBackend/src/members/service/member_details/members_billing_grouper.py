"""Builds the per-membership cards + overview for the CRM member detail."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.members.schema.members_billing_schema import (
    BillingMembershipInfo,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.members_status_mapping import (
    is_membership_overdue,
)
from src.memberships.memberships_schema import (
    MemberMembershipsAppliedDiscount,
)
from src.shared.formatters import format_minor_units


class MembershipOverviewContext(BaseModel):
    """Resolved inputs for the profile-header overview string.

    The detail service computes this from the viewed member's own
    membership rows (it owns the scan); the grouper only formats it.
    ``total`` is the member's own active-recurring monthly sum, in minor
    units.
    """

    model_config = ConfigDict(frozen=True)

    total: int
    has_trial: bool
    has_cancelled: bool
    has_frozen: bool
    has_overdue: bool
    paying_count: int  # active recurring count among the member's own


class MembersBillingGrouper:
    """Builds the member-detail carousel cards + the overview string.

    The carousel is scoped to the viewed member and ``member_details.sql``
    returns one row per (member, plan), so each row becomes exactly one
    membership card — there is no cross-member grouping.
    """

    def build_membership_cards(
        self,
        membership_rows: list,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        today: date,
    ) -> list[BillingMembershipInfo]:
        """Build one card per membership row.

        Args:
            membership_rows: The viewed member's own membership rows.
            usage_lookup: (member_id, item_id) -> per-cycle class usage.
            today: The gym's local current date, used to derive overdue.

        Returns:
            One BillingMembershipInfo per row.
        """
        return [
            self._build_card(row, usage_lookup, today)
            for row in membership_rows
        ]

    def _build_card(
        self,
        row: dict,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        today: date,
    ) -> BillingMembershipInfo:
        """Build a single membership card from one row.

        ``total_price`` is the membership's own post-discount share kept as
        stored regardless of status (the status badge conveys frozen /
        cancelled). The per-cycle class usage is inlined directly onto the
        card, defaulting to None / 0 when the member has no usage row.

        Args:
            row: One ``member_details.sql``-shaped membership row.
            usage_lookup: (member_id, item_id) -> per-cycle class usage.
            today: The gym's local current date, used to derive overdue.

        Returns:
            The membership card.
        """
        usage = usage_lookup.get((row["member_id"], row["item_id"]))
        return BillingMembershipInfo(
            plan_id=row["plan_id"],
            plan_name=row["plan_name"],
            plan_type=row["plan_type"],
            status=self._display_status(
                row["membership_status"],
                row["next_due_date"],
                today,
            ),
            item_id=row["item_id"],
            paid_by_member_id=row["paid_by_member_id"],
            base_cost=row["base_cost"],
            current_active_price=row["current_active_price"],
            on_outdated_price=bool(row["on_outdated_price"]),
            duration_amount=row["duration_amount"],
            duration_unit=row["duration_unit"],
            total_price=row["total_price"] or 0,
            last_paid_date=row["last_paid_date"],
            next_due_date=row["next_due_date"],
            start_date=row["membership_start_date"],
            end_date=row["membership_end_date"],
            cancel_date=row["membership_cancel_date"],
            freeze_start_date=row["freeze_start_date"],
            freeze_end_date=row["freeze_end_date"],
            class_count=(usage.class_count if usage is not None else None),
            classes_used=(usage.classes_used if usage is not None else 0),
            classes_remaining=(
                usage.classes_remaining if usage is not None else None
            ),
            discounts=self._collect_discounts(row),
        )

    def build_membership_overview(
        self,
        ctx: MembershipOverviewContext,
    ) -> str:
        """Build the profile-header overview string for the viewed member.

        ``Paying $X/mo for N Membership(s)`` in the normal paying state;
        salient account states (frozen / overdue / trial / cancelled)
        short-circuit the price phrase and keep their existing strings, with
        the count suffix appended when something is still active.

        Args:
            ctx: Resolved overview inputs from the detail service.

        Returns:
            The overview string.
        """
        state = self._state_phrase(ctx)
        suffix = self._count_suffix(ctx.paying_count)
        if state is None:
            return f"Paying {format_minor_units(ctx.total)}/mo{suffix}"
        if ctx.paying_count > 0:
            return f"{state}{suffix}"
        return state

    def _count_suffix(self, paying_count: int) -> str:
        """`` for N Membership(s)`` suffix, or empty when nothing active."""
        if paying_count <= 0:
            return ""
        label = "Membership" if paying_count == 1 else "Memberships"
        return f" for {paying_count} {label}"

    def _state_phrase(self, ctx: MembershipOverviewContext) -> str | None:
        """Salient account-state string, or ``None`` for normal paying.

        Returns ``None`` only for the normal positive-paying state so the
        caller supplies the price phrasing; every other state (frozen /
        overdue / active-without-total / trial / cancelled / none) returns
        its display string directly.
        """
        if ctx.has_frozen:
            return "Account is Frozen"
        if ctx.has_overdue:
            if ctx.total > 0:
                return f"Overdue · {format_minor_units(ctx.total)}/mo"
            return "Overdue"
        if ctx.total > 0:
            return None
        if ctx.paying_count > 0:
            return "Active"
        if ctx.has_trial:
            return "Member is on Trial"
        if ctx.has_cancelled:
            return "Membership is Cancelled"
        return "No active memberships"

    def _display_status(
        self,
        raw_status: str,
        next_due: date | None,
        today: date,
    ) -> CrmMemberStatus:
        """Map a raw DB membership status to its CRM display status.

        Returns ``overdue`` for a non-cancelled membership whose next
        due date has passed; otherwise the raw status unchanged.

        Args:
            raw_status: The DB-derived membership status.
            next_due: The membership's next due date, if any.
            today: The gym's local current date.

        Returns:
            The CRM-facing membership status.
        """
        if is_membership_overdue(raw_status, next_due, today):
            return CrmMemberStatus.overdue
        return CrmMemberStatus(raw_status)

    def _collect_discounts(
        self,
        row: dict,
    ) -> list[MemberMembershipsAppliedDiscount]:
        """Collect the active applied-discount rows for one membership.

        ``member_details.sql`` builds the ``applied_discounts`` JSONB list
        per item (already filtered to currently-active rows), each resolved
        to its pinned value version. Applied-discount rows are item-scoped,
        so they are NOT de-duplicated — the CRM removes one by
        ``applied_discount_id``.

        Args:
            row: One membership row.

        Returns:
            One MemberMembershipsAppliedDiscount per active applied-discount.
        """
        return [
            MemberMembershipsAppliedDiscount(**applied)
            for applied in row["applied_discounts"] or []
        ]
