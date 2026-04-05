"""Service for calculating membership prices across a family account."""

from datetime import date
from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType

from src.shared.membership_pricing.membership_pricing_schema import (
    AccountPricingInput,
    AccountPricingResult,
    DiscountInput,
    MembershipPriceResult,
    PlanInput,
)


class MembershipPricingService:
    """Calculates membership prices and builds cost formula strings.

    Stateless service — no database access, no DI needed.
    """

    def calculate_account_prices(
        self,
        account_input: AccountPricingInput,
    ) -> AccountPricingResult:
        """Calculate prices for all memberships in the account.

        For each membership:
        1. Start with plan base_cost
        2. If additional member and plan has discount: apply % off
        3. Apply each gym discount (percentage or dollar off)
        4. Floor at $0
        5. Build formula string

        Args:
            account_input: All membership, plan, and discount data.

        Returns:
            Account-level total and per-membership itemized results.
        """
        results: list[MembershipPriceResult] = []
        active_total = 0.0
        frozen_total = 0.0
        has_trial = False
        has_cancelled = False
        paying_count = 0

        for membership in account_input.memberships:
            if membership.status == MembershipDbStatus.cancelled:
                has_cancelled = True
                continue

            plan = account_input.plans[membership.plan_id]

            if plan.plan_type == PlanType.trial:
                has_trial = True
                continue

            paying_count += 1
            discounts = self._resolve_discounts(
                membership.discount_ids,
                account_input.discounts,
            )

            price, formula = self._calculate_single_membership(
                plan=plan,
                discounts=discounts,
                is_additional_member=membership.is_additional_member,
            )

            results.append(
                MembershipPriceResult(
                    crm_user_id=membership.crm_user_id,
                    plan_id=membership.plan_id,
                    calculated_price=price,
                    cost_formula=formula,
                )
            )

            if membership.status == MembershipDbStatus.frozen:
                frozen_total += price
            else:
                active_total += price

        return AccountPricingResult(
            active_total=round(active_total, 2),
            frozen_total=round(frozen_total, 2),
            has_trial=has_trial,
            has_cancelled=has_cancelled,
            paying_count=paying_count,
            membership_prices=results,
        )

    def _calculate_single_membership(
        self,
        plan: PlanInput,
        discounts: list[DiscountInput],
        is_additional_member: bool,
    ) -> tuple[float, str | None]:
        """Calculate price and formula for one membership.

        Args:
            plan: The membership plan details.
            discounts: Resolved active discounts for this membership.
            is_additional_member: Whether this is a linked member.

        Returns:
            Tuple of (calculated_price, cost_formula).
        """
        price = plan.base_cost
        formula_parts: list[str] = [f"${plan.base_cost:.2f}"]
        has_adjustments = False

        if is_additional_member and plan.additional_member_discount:
            discount_pct = plan.additional_member_discount
            price = price * (1 - discount_pct / 100)
            formula_parts.append(f"- {discount_pct:.0f}% (Additional Member)")
            has_adjustments = True

        today = date.today()
        for d in discounts:
            if d.end_date and d.end_date < today:
                continue

            if d.percentage_off:
                price = price * (1 - d.percentage_off / 100)
                formula_parts.append(f"- {d.percentage_off:.0f}% ({d.discount_name})")
                has_adjustments = True
            elif d.dollar_off:
                price = price - d.dollar_off
                formula_parts.append(f"- ${d.dollar_off:.2f} ({d.discount_name})")
                has_adjustments = True

        price = max(price, 0.0)
        price = round(price, 2)

        if not has_adjustments:
            return price, None

        formula_parts.append(f"= ${price:.2f}")
        formula = " ".join(formula_parts)

        return price, formula

    def _resolve_discounts(
        self,
        discount_ids: list[UUID],
        all_discounts: dict[UUID, DiscountInput],
    ) -> list[DiscountInput]:
        """Resolve discount IDs to DiscountInput objects.

        Args:
            discount_ids: UUIDs from the membership row.
            all_discounts: All available gym discounts keyed by ID.

        Returns:
            List of matching DiscountInput objects.
        """
        resolved = []
        for uid in discount_ids:
            discount = all_discounts.get(uid)
            if discount:
                resolved.append(discount)
        return resolved
