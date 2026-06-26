"""Resolve each consolidated line's discount coupons + own the discount math."""

from enum import IntEnum
from uuid import UUID

from src.payments.schema.payments_discount_schema import (
    PaymentsCouponValue,
)
from src.payments.schema.payments_members_schema import (
    SubscriptionItemDiscount,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.sync.sync_schema import (
    ActiveMembershipRow,
    LineDiscountValue,
    ResolvedDiscounts,
)


class DiscountApplicationKind(IntEnum):
    """Discount kinds ordered by application sequence."""

    percent = 0
    dollar = 1


# Percent before dollar — used by both coupon attach order and per-membership math.
DISCOUNT_APPLICATION_ORDER: tuple[DiscountApplicationKind, ...] = (
    DiscountApplicationKind.percent,
    DiscountApplicationKind.dollar,
)

# Stripe percent_off has 2-decimal precision; drop any value that rounds to 0.00%.
_PERCENT_OFF_DECIMALS = 2
_MIN_LINE_PERCENT_OFF = 0.01


class PaymentSyncDiscounts:
    """Aggregate per-line discount math and find-or-create Stripe coupons.

    Percents compound within a membership then average across the line (÷qty);
    dollars sum. Frozen memberships contribute a synthetic 100%-off so they bill
    $0 while staying on the subscription. No DB writes; safe in preview.
    """

    def __init__(
        self,
        discount_service: PaymentsStripeDiscountService,
    ) -> None:
        self._discounts = discount_service

    async def resolve(
        self,
        groups: dict[UUID, list[ActiveMembershipRow]],
        stripe_account_id: str,
    ) -> ResolvedDiscounts:
        """Aggregate discounts per price line and find-or-create their Stripe coupons."""
        coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]] = {}
        links: dict[UUID, str] = {}
        membership_amounts: dict[UUID, int] = {}
        for price_id, memberships in groups.items():
            values, group_amounts = self._aggregate_line_values(memberships)
            membership_amounts.update(group_amounts)
            if not values:
                continue
            ordered_values = sorted(values, key=self._application_rank)  # percent before dollar
            item_discounts: list[SubscriptionItemDiscount] = []
            for value in ordered_values:
                coupon_id = await self._discounts.find_or_create_for_value(
                    PaymentsCouponValue(
                        percentage_off=value.percentage_off,
                        dollar_off=value.dollar_off,
                    ),
                    stripe_account_id,
                )
                item_discounts.append(
                    SubscriptionItemDiscount(coupon=coupon_id)
                )
                for applied_discount_id in value.contributing_ids:
                    links[applied_discount_id] = coupon_id
            coupons_by_price[price_id] = item_discounts
        return ResolvedDiscounts(
            coupons_by_price=coupons_by_price,
            links=links,
            membership_amounts=membership_amounts,
        )

    @staticmethod
    def _application_rank(value: LineDiscountValue) -> int:
        """Sort key: percent before dollar (matches DISCOUNT_APPLICATION_ORDER)."""
        kind = (
            DiscountApplicationKind.percent
            if value.percentage_off is not None
            else DiscountApplicationKind.dollar
        )
        return DISCOUNT_APPLICATION_ORDER.index(kind)

    # ── Discount Math ───────────────────────────────────────────────

    def _remaining_after_percents(self, percents: list[float]) -> float:
        """Π(1 − p/100) — multiplicative remaining fraction after sequential percents."""
        remaining = 1.0
        for percent in percents:
            remaining *= 1 - percent / 100
        return remaining

    def _post_discount_amount(
        self,
        base_price: int,
        percents: list[float],
        dollar_sum: int,
    ) -> int:
        """Membership's post-discount price: compound percents then subtract dollars, floor 0."""
        price = float(base_price)
        for kind in DISCOUNT_APPLICATION_ORDER:
            if kind is DiscountApplicationKind.percent:
                price *= self._remaining_after_percents(percents)
            else:
                price -= dollar_sum
        return max(0, round(price))

    def _aggregate_line_values(
        self,
        memberships: list[ActiveMembershipRow],
    ) -> tuple[list[LineDiscountValue], dict[UUID, int]]:
        """Aggregate line discount values and per-membership post-discount amounts.

        Returns at most one percent value and one dollar value for the line, plus
        each membership's own post-discount price.
        """
        divisor = len(memberships) if memberships else 1
        effective_fraction = 0.0
        dollar_sum = 0
        percent_ids: list[UUID] = []
        dollar_ids: list[UUID] = []
        membership_amounts: dict[UUID, int] = {}

        for membership in memberships:
            mem_percents: list[float] = []
            mem_dollars = 0
            mem_percent_ids: list[UUID] = []
            mem_dollar_ids: list[UUID] = []
            for discount in membership.discounts:
                if discount.percentage_off:
                    mem_percent_ids.append(discount.applied_discount_id)
                    mem_percents.append(discount.percentage_off)
                if discount.dollar_off:
                    mem_dollar_ids.append(discount.applied_discount_id)
                    mem_dollars += discount.dollar_off
            membership_amounts[membership.item_id] = self._post_discount_amount(
                membership.price, mem_percents, mem_dollars
            )
            if membership.is_frozen:
                # Synthetic 100%-off: bills $0 but stays on the subscription.
                # Dollar ids ride the percent coupon so they aren't stranded.
                effective_fraction += 1.0
                percent_ids.extend(mem_percent_ids)
                percent_ids.extend(mem_dollar_ids)
                continue
            percent_ids.extend(mem_percent_ids)
            dollar_ids.extend(mem_dollar_ids)
            effective_fraction += 1 - self._remaining_after_percents(mem_percents)
            dollar_sum += mem_dollars

        values: list[LineDiscountValue] = []
        line_percent = effective_fraction / divisor * 100
        if round(line_percent, _PERCENT_OFF_DECIMALS) >= _MIN_LINE_PERCENT_OFF:
            values.append(
                LineDiscountValue(
                    percentage_off=line_percent,
                    contributing_ids=percent_ids,
                )
            )
        if dollar_sum > 0:
            values.append(
                LineDiscountValue(
                    dollar_off=dollar_sum,
                    contributing_ids=dollar_ids,
                )
            )
        return values, membership_amounts
