"""Groups membership rows by plan for the CRM member detail carousel."""

from collections import defaultdict
from uuid import UUID

from src.members.schema.members_billing_schema import (
    BillingDiscountInfo,
    BillingMembershipInfo,
    BillingMembershipMemberInfo,
    BillingPayingForMember,
)
from src.members.service.member_details.members_billing_supplementary import (
    MembersBillingSupplementary,
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
        target_member_id: UUID,
    ) -> list[BillingMembershipInfo]:
        """Group membership rows by plan_id.

        Args:
            membership_rows: Rows with membership data.
            supplementary: For discount and profile lookups.
            target_member_id: The member whose profile is being viewed,
                used to pin them to the top of each card's paying_for list.

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
                plan_id,
                target_member_id,
            )

            total_price = representative["total_price"] or 0
            all_discounts = self._collect_plan_discounts(rows, supplementary)

            members = {
                row["member_id"]: BillingMembershipMemberInfo(
                    item_id=row["item_id"],
                    end_date=row["membership_end_date"],
                    cancel_date=row["membership_cancel_date"],
                    on_outdated_price=bool(row["on_outdated_price"]),
                )
                for row in rows
            }

            grouped.append(
                BillingMembershipInfo(
                    plan_id=plan_id,
                    plan_name=representative["plan_name"],
                    plan_type=representative["plan_type"],
                    status=representative["membership_status"],
                    base_cost=representative["base_cost"],
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

    def _build_paying_for(
        self,
        rows: list,
        supplementary: MembersBillingSupplementary,
        plan_id: UUID,
        target_member_id: UUID,
    ) -> list[BillingPayingForMember]:
        """Build the paying_for list for a plan group.

        Args:
            rows: All membership rows sharing the same plan.
            supplementary: For profile lookups.
            plan_id: The plan to look up usage for.
            target_member_id: The queried member, pinned to index 0.

        Returns:
            BillingPayingForMember list, queried member first.
        """
        paying_for: list[BillingPayingForMember] = []
        for row in rows:
            uid = row["member_id"]
            profile = supplementary.profiles_dict.get(uid)

            fields: dict = {
                "member_id": uid,
                "status": row["membership_status"],
                "first_name": (profile.first_name if profile else row["first_name"]),
                "last_name": (profile.last_name if profile else row["last_name"]),
                "photo_url": (profile.photo_url if profile else row.get("photo_url")),
            }

            paying_for.append(BillingPayingForMember(**fields))

        paying_for.sort(key=lambda p: p.member_id != target_member_id)
        return paying_for

    def _collect_plan_discounts(
        self,
        rows: list,
        supplementary: MembersBillingSupplementary,
    ) -> list[BillingDiscountInfo]:
        """Collect unique discounts across all rows for a plan.

        Args:
            rows: Membership rows sharing the same plan.
            supplementary: For discount lookups.

        Returns:
            De-duplicated list of BillingDiscountInfo objects.
        """
        seen: set[UUID] = set()
        discounts: list[BillingDiscountInfo] = []
        for row in rows:
            for d in supplementary.get_discounts(row["discount_ids"]):
                if d.discount_id not in seen:
                    seen.add(d.discount_id)
                    discounts.append(d)
        return discounts

    def _build_price_summary(
        self,
        monthly_total: int,
        has_trial: bool,
        has_cancelled: bool,
        has_frozen: bool,
        paying_count: int,
    ) -> str:
        """Build a price summary string.

        Returns strings like:
        - "Account is Frozen"
        - "Paying $320/mo"
        - "Active"
        - "Member is on Trial"
        - "Membership is Cancelled"

        Args:
            monthly_total: Parent's total_monthly_recurring_price in minor units.
            has_trial: Whether any membership is a trial.
            has_cancelled: Whether any membership is cancelled.
            has_frozen: Whether any membership is frozen.
            paying_count: Count of active recurring memberships.

        Returns:
            Summary string.
        """
        if has_frozen:
            return "Account is Frozen"
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
