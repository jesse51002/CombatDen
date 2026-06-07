"""Groups membership rows by plan for the CRM member detail carousel."""

from collections import defaultdict
from datetime import date
from uuid import UUID

from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsAppliedDiscount,
)
from src.members.schema.members_billing_schema import (
    BillingMembershipInfo,
    BillingMembershipMemberInfo,
    BillingPayingForMember,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.members_billing_supplementary import (
    MembersBillingSupplementary,
)
from src.members.service.members_status_mapping import (
    is_membership_overdue,
)
from src.shared.formatters import format_minor_units


class MembersBillingGrouper:
    """Groups membership rows by plan_id for the membership carousel.

    Also handles linked-account filtering and overview string generation.
    """

    def group_by_plan(
        self,
        membership_rows: list,
        supplementary: MembersBillingSupplementary,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        target_member_id: UUID,
        today: date,
    ) -> list[BillingMembershipInfo]:
        """Group membership rows by plan_id.

        Args:
            membership_rows: Rows with membership data.
            supplementary: For discount and profile lookups.
            usage_lookup: (member_id, plan_id) -> per-cycle class usage.
            target_member_id: The member whose profile is being viewed,
                used to pin them to the top of each card's paying_for list.
            today: The gym's local current date, used to derive overdue.

        Returns:
            List of BillingMembershipInfo, one per unique plan.
        """
        plan_rows: dict[UUID, list] = defaultdict(list)
        for row in membership_rows:
            plan_rows[row["plan_id"]].append(row)

        grouped: list[BillingMembershipInfo] = []
        for plan_id, rows in plan_rows.items():
            representative = rows[0]

            paying_for = self._build_paying_for(
                rows,
                supplementary,
                usage_lookup,
                plan_id,
                target_member_id,
                today,
            )

            total_price = representative["total_price"] or 0
            all_discounts = self._collect_plan_discounts(rows)

            members = {
                row["member_id"]: BillingMembershipMemberInfo(
                    item_id=row["item_id"],
                    end_date=row["membership_end_date"],
                    cancel_date=row["membership_cancel_date"],
                    on_outdated_price=bool(row["on_outdated_price"]),
                    base_cost=row["base_cost"],
                    total_price=row["total_price"] or 0,
                )
                for row in rows
            }

            grouped.append(
                BillingMembershipInfo(
                    plan_id=plan_id,
                    plan_name=representative["plan_name"],
                    plan_type=representative["plan_type"],
                    status=self._display_status(
                        representative["membership_status"],
                        representative["next_due_date"],
                        today,
                    ),
                    base_cost=representative["base_cost"],
                    current_active_price=representative[
                        "current_active_price"
                    ],
                    duration_amount=representative["duration_amount"],
                    duration_unit=representative["duration_unit"],
                    total_price=total_price,
                    last_paid_date=representative["last_paid_date"],
                    next_due_date=representative["next_due_date"],
                    start_date=representative["membership_start_date"],
                    freeze_start_date=representative["freeze_start_date"],
                    freeze_end_date=representative["freeze_end_date"],
                    paying_for=paying_for,
                    discounts=all_discounts,
                    members=members,
                )
            )

        return grouped

    def filter_plans_for_member(
        self,
        all_grouped: list[BillingMembershipInfo],
        member_id: UUID,
    ) -> list[BillingMembershipInfo]:
        """Filter grouped plans to only those covering the target member.

        Used when the queried member is a linked (child) account.

        Args:
            all_grouped: Full list of grouped plans.
            member_id: The queried member's ID.

        Returns:
            Plans where the member_id is present in ``members``.
        """
        return [plan for plan in all_grouped if member_id in plan.members]

    def build_membership_overview(
        self,
        linked_to_id: UUID | None,
        monthly_total: int,
        has_trial: bool,
        has_cancelled: bool,
        has_frozen: bool,
        has_overdue: bool,
        paying_count: int,
        supplementary: MembersBillingSupplementary,
    ) -> tuple[str, UUID | None]:
        """Build the membership overview string and linked_to_account value.

        Args:
            linked_to_id: The parent account ID if the member is linked.
            monthly_total: Parent's total_monthly_recurring_price in minor units.
            has_trial: Whether any membership is a trial.
            has_cancelled: Whether any membership is cancelled.
            has_frozen: Whether any membership is frozen.
            has_overdue: Whether any membership is overdue.
            paying_count: Number of active recurring memberships.
            supplementary: For profile lookups.

        Returns:
            Tuple of (overview_string, linked_to_account_id).
        """
        summary = self._build_price_summary(
            monthly_total,
            has_trial,
            has_cancelled,
            has_frozen,
            has_overdue,
            paying_count,
        )

        if linked_to_id is None:
            if paying_count > 0:
                label = "Membership" if paying_count == 1 else "Memberships"
                return f"{summary} for {paying_count} {label}", None
            return summary, None

        primary = supplementary.profiles_dict.get(linked_to_id)
        name = primary.first_name if primary else "Primary"

        return f"Account is paid for by {name} ({summary})", linked_to_id

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

    def _build_paying_for(
        self,
        rows: list,
        supplementary: MembersBillingSupplementary,
        usage_lookup: dict[tuple[UUID, UUID], MembershipUsage],
        plan_id: UUID,
        target_member_id: UUID,
        today: date,
    ) -> list[BillingPayingForMember]:
        """Build the paying_for list for a plan group.

        Args:
            rows: All membership rows sharing the same plan.
            supplementary: For profile lookups.
            usage_lookup: (member_id, plan_id) -> per-cycle class usage.
            plan_id: The plan to look up usage for.
            target_member_id: The queried member, pinned to index 0.
            today: The gym's local current date, used to derive overdue.

        Returns:
            BillingPayingForMember list, queried member first.
        """
        paying_for: list[BillingPayingForMember] = []
        for row in rows:
            uid = row["member_id"]
            profile = supplementary.profiles_dict.get(uid)

            fields: dict = {
                "member_id": uid,
                "status": self._display_status(
                    row["membership_status"],
                    row["next_due_date"],
                    today,
                ),
                "first_name": (profile.first_name if profile else row["first_name"]),
                "last_name": (profile.last_name if profile else row["last_name"]),
                "photo_url": (profile.photo_url if profile else row.get("photo_url")),
            }

            usage = usage_lookup.get((uid, plan_id))
            if usage is not None:
                fields["class_count"] = usage.class_count
                fields["classes_used"] = usage.classes_used
                fields["classes_remaining"] = usage.classes_remaining

            paying_for.append(BillingPayingForMember(**fields))

        paying_for.sort(key=lambda p: p.member_id != target_member_id)
        return paying_for

    def _collect_plan_discounts(
        self,
        rows: list,
    ) -> list[MemberMembershipsAppliedDiscount]:
        """Collect every active applied-discount snapshot across a plan's rows.

        Each row carries an ``applied_discounts`` JSONB list built by
        ``member_details.sql`` from the membership's applied-discount
        snapshots (already filtered to currently-active ones), each
        resolved to its pinned value version. Snapshots are item-scoped, so
        they are NOT de-duplicated — the CRM groups them under each covered
        member by ``item_id`` and removes one by ``applied_discount_id``.

        Args:
            rows: Membership rows sharing the same plan.

        Returns:
            One MemberMembershipsAppliedDiscount per active snapshot.
        """
        discounts: list[MemberMembershipsAppliedDiscount] = []
        for row in rows:
            for applied in row["applied_discounts"] or []:
                discounts.append(MemberMembershipsAppliedDiscount(**applied))
        return discounts

    def _build_price_summary(
        self,
        monthly_total: int,
        has_trial: bool,
        has_cancelled: bool,
        has_frozen: bool,
        has_overdue: bool,
        paying_count: int,
    ) -> str:
        """Build a price summary string.

        Returns strings like:
        - "Account is Frozen"
        - "Overdue · $320/mo"
        - "Overdue"
        - "Paying $320/mo"
        - "Active"
        - "Member is on Trial"
        - "Membership is Cancelled"

        Args:
            monthly_total: Parent's total_monthly_recurring_price in minor units.
            has_trial: Whether any membership is a trial.
            has_cancelled: Whether any membership is cancelled.
            has_frozen: Whether any membership is frozen.
            has_overdue: Whether any membership is overdue.
            paying_count: Count of active recurring memberships.

        Returns:
            Summary string.
        """
        if has_frozen:
            return "Account is Frozen"
        if has_overdue:
            # Frozen pauses billing and wins above; otherwise an overdue
            # membership is the salient state. Keep the price context when
            # the denormalised monthly total has been written.
            if monthly_total > 0:
                return f"Overdue · {format_minor_units(monthly_total)}/mo"
            return "Overdue"
        if monthly_total > 0:
            return f"Paying {format_minor_units(monthly_total)}/mo"
        if paying_count > 0:
            # Active recurring memberships exist but the denormalised
            # monthly total has not been written yet (seed data, or the
            # Stripe price write-back has not run). Report the active
            # state instead of falsely claiming there are none.
            return "Active"
        if has_trial:
            return "Member is on Trial"
        if has_cancelled:
            return "Membership is Cancelled"
        return "No active memberships"
