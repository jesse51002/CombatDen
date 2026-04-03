"""Groups membership rows by plan for the carousel display."""

from collections import defaultdict
from uuid import UUID

from src.members.schema.member_details_schema import (
    DiscountInfo,
    LinkedAccount,
    MembershipInfo,
)
from src.members.service.member_details.member_details_supplementary import (
    MemberDetailsSupplementary,
)
from src.shared.membership_pricing.membership_pricing_schema import (
    AccountPricingResult,
    MembershipPriceResult,
)


class MemberDetailsMembershipGrouper:
    """Groups membership rows by plan_id for the carousel.

    Also handles linked-account filtering and overview string
    generation.
    """

    def group_by_plan(
        self,
        membership_rows: list,
        pricing_result: AccountPricingResult,
        supplementary: MemberDetailsSupplementary,
    ) -> list[MembershipInfo]:
        """Group membership rows by plan_id.

        Args:
            membership_rows: Rows with membership data.
            pricing_result: Calculated prices per membership.
            supplementary: For discount and profile lookups.

        Returns:
            List of MembershipInfo, one per unique plan.
        """
        price_lookup: dict[tuple[UUID, UUID], MembershipPriceResult] = {
            (p.crm_user_id, p.plan_id): p for p in pricing_result.membership_prices
        }

        plan_rows: dict[UUID, list] = defaultdict(list)
        for row in membership_rows:
            plan_rows[row["plan_id"]].append(row)

        grouped: list[MembershipInfo] = []
        for plan_id, rows in plan_rows.items():
            representative = rows[0]

            paying_for = self._build_paying_for(
                rows,
                supplementary,
            )

            priced_rows = [r for r in rows if (r["crm_user_id"], plan_id) in price_lookup]

            total_cost = sum(
                price_lookup[(r["crm_user_id"], plan_id)].calculated_price for r in priced_rows
            )

            first_price = price_lookup.get((representative["crm_user_id"], plan_id)) or (
                price_lookup[(priced_rows[0]["crm_user_id"], plan_id)] if priced_rows else None
            )

            all_discounts = self._collect_plan_discounts(
                rows,
                supplementary,
            )

            grouped.append(
                MembershipInfo(
                    plan_id=plan_id,
                    plan_name=representative["plan_name"],
                    plan_type=representative["plan_type"],
                    status=representative["membership_status"],
                    base_cost=representative["base_cost"],
                    billing_cycle=representative["duration_unit"],
                    total_cost=total_cost,
                    cost_formula=first_price.cost_formula if first_price else None,
                    additional_member_discount=(representative["additional_member_discount"]),
                    last_paid_date=representative["last_paid_date"],
                    next_due_date=representative["next_due_date"],
                    start_date=representative["membership_start_date"],
                    paying_for=paying_for,
                    discounts=all_discounts,
                )
            )

        return grouped

    def filter_plans_for_member(
        self,
        grouped: list[MembershipInfo],
        crm_user_id: UUID,
    ) -> list[MembershipInfo]:
        """Filter grouped plans to only those the member is in.

        Used when the queried user is a linked account, so the
        carousel only shows plans they participate in.

        Args:
            grouped: All grouped plan memberships.
            crm_user_id: The linked member's ID.

        Returns:
            Filtered list of MembershipInfo.
        """
        return [m for m in grouped if any(p.crm_user_id == crm_user_id for p in m.paying_for)]

    def build_membership_overview(
        self,
        linked_to_id: UUID | None,
        active_total: float,
        frozen_total: float,
        has_trial: bool,
        has_cancelled: bool,
        paying_count: int,
        supplementary: MemberDetailsSupplementary,
    ) -> tuple[str, UUID | None]:
        """Build the membership overview string.

        Args:
            linked_to_id: Primary account ID if linked, else None.
            active_total: Total price of active memberships.
            frozen_total: Total price of frozen memberships.
            has_trial: Whether any membership is a trial.
            has_cancelled: Whether any membership is cancelled.
            paying_count: Count of paying memberships (excl trial/cancelled).
            supplementary: For profile name lookups.

        Returns:
            Tuple of (overview_string, linked_to_account_uuid).
        """
        summary = _build_price_summary(
            active_total,
            frozen_total,
            has_trial,
            has_cancelled,
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
        supplementary: MemberDetailsSupplementary,
    ) -> list[LinkedAccount]:
        """Build the paying_for list for a plan group.

        Args:
            rows: All membership rows sharing the same plan.
            supplementary: For profile lookups.

        Returns:
            LinkedAccount list for each member on this plan.
        """
        paying_for = []
        for row in rows:
            uid = row["crm_user_id"]
            profile = supplementary.profiles_dict.get(uid)
            if profile:
                paying_for.append(profile)
            else:
                paying_for.append(
                    LinkedAccount(
                        crm_user_id=uid,
                        first_name=row["first_name"],
                        last_name=row["last_name"],
                        photo_url=row["photo_url"],
                    )
                )
        return paying_for

    def _collect_plan_discounts(
        self,
        rows: list,
        supplementary: MemberDetailsSupplementary,
    ) -> list[DiscountInfo]:
        """Collect unique discounts across all rows for a plan.

        Args:
            rows: Membership rows sharing the same plan.
            supplementary: For discount lookups.

        Returns:
            De-duplicated list of DiscountInfo objects.
        """
        seen: set[UUID] = set()
        discounts: list[DiscountInfo] = []
        for row in rows:
            for d in supplementary.get_discounts(
                row["discount_ids"],
            ):
                if d.discount_id not in seen:
                    seen.add(d.discount_id)
                    discounts.append(d)
        return discounts


def _build_price_summary(
    active_total: float,
    frozen_total: float,
    has_trial: bool,
    has_cancelled: bool,
) -> str:
    """Build a price summary string from active/frozen totals.

    Returns strings like:
    - "Paying $320/mo" (only active)
    - "Frozen $100/mo" (only frozen)
    - "Paying $320/mo, Frozen $100/mo" (both)
    - "Member is on Trial" (only trial, no paying/frozen)
    - "Membership is Cancelled" (only cancelled, no paying/frozen/trial)

    Args:
        active_total: Total price of active memberships.
        frozen_total: Total price of frozen memberships.
        has_trial: Whether any membership is a trial.
        has_cancelled: Whether any membership is cancelled.

    Returns:
        Summary string.
    """
    parts: list[str] = []
    if active_total > 0:
        parts.append(f"Paying {_format_dollar(active_total)}/mo")
    if frozen_total > 0:
        parts.append(f"Frozen {_format_dollar(frozen_total)}/mo")
    if not parts:
        if has_trial:
            return "Member is on Trial"
        if has_cancelled:
            return "Membership is Cancelled"
        return "No active memberships"
    return ", ".join(parts)


def _format_dollar(amount: float) -> str:
    """Format a dollar amount as '$165' or '$165.50'.

    Args:
        amount: Dollar amount.

    Returns:
        Formatted dollar string.
    """
    if amount == int(amount):
        return f"${int(amount)}"
    return f"${amount:.2f}"
