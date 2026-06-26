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
    """The two discount kinds, ordered by how they sequence on a line."""

    percent = 0
    dollar = 1


# Single source of truth for the order a line's discounts apply — percent
# first, then dollar. Used by BOTH the Stripe coupon attach order (`resolve`)
# and the per-membership math: percent-first lands the percent on the uniform unit
# base and leaves the dollar purely additive, so each membership's own discounted
# price sums to the consolidated line total with no rescaling.
DISCOUNT_APPLICATION_ORDER: tuple[DiscountApplicationKind, ...] = (
    DiscountApplicationKind.percent,
    DiscountApplicationKind.dollar,
)


class PaymentSyncDiscounts:
    """Owns the discount math and resolves each line's coupons at build time.

    For each consolidated line (a price group of memberships) it aggregates the
    memberships' discounts into at most one percent value and one dollar value —
    percents compound **sequentially within a membership** then average across the
    line (÷ quantity), dollars sum — find-or-creates the deterministic coupon per value
    on the gym's Connect account, and orders them **percent before dollar**
    (``DISCOUNT_APPLICATION_ORDER``) so Stripe applies them sequentially in that
    order (we do only the percentage-level math; Stripe sequences percent→dollar
    on the line).

    **Freeze rides this math** (it is not a pause/drop): a frozen membership
    (``ActiveMembershipRow.is_frozen``) contributes a synthetic 100%-off to its
    line, so it bills $0 while STAYING on the subscription with its line id — a
    consolidated line bills only its non-frozen units. So a frozen member's row
    is always `applied` with a real `stripe_item_id`, and unfreeze is just the
    next converge dropping the synthetic 100%-off.

    The discounts arrive **already date-filtered by the read** (the query excludes
    any past its end_date as of the gym-timezone today), so the math has no date
    logic of its own. Runs inside the build for **both** the real sync and
    preview, so preview reflects discounts. It does **no DB writes**: it returns
    the per-price coupon lists (for the builder to attach onto the bucket items)
    and the ``applied_discount_id → coupon_id`` links (for the real path to write
    back). Coupon find-or-create is idempotent and gym-wide, so it is safe in
    preview.
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
        """Resolve the coupons for each price line.

        Returns a ``ResolvedDiscounts``:
        - ``coupons_by_price``: ``price_id → [SubscriptionItemDiscount...]`` for
          the builder to attach onto each consolidated line (percent coupon
          first, then dollar, so Stripe sequences percent→dollar).
        - ``links``: ``applied_discount_id → coupon_id`` for the real path to
          write back onto each contributing row.
        - ``membership_amounts``: each membership's ``item_id`` → its own
          post-discount price (plan price with all its currently active
          discounts), for **every** membership.

        ``coupons_by_price`` / ``links`` are empty when no line carries a
        discount; ``membership_amounts`` always covers every membership.
        """
        coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]] = {}
        links: dict[UUID, str] = {}
        membership_amounts: dict[UUID, int] = {}
        for price_id, memberships in groups.items():
            values, group_amounts = self._aggregate_line_values(memberships)
            membership_amounts.update(group_amounts)
            if not values:
                continue
            # Percent (`percent_off`) before dollar (`amount_off`) so Stripe
            # sequences percent→dollar on the line (DISCOUNT_APPLICATION_ORDER).
            ordered_values = sorted(values, key=self._application_rank)
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
        """Sort key placing a value by ``DISCOUNT_APPLICATION_ORDER``.

        Percent values rank before dollar values, so the attach order Stripe
        applies matches the per-membership math (percent→dollar).
        """
        kind = (
            DiscountApplicationKind.percent
            if value.percentage_off is not None
            else DiscountApplicationKind.dollar
        )
        return DISCOUNT_APPLICATION_ORDER.index(kind)

    # ── Discount Math ───────────────────────────────────────────────

    def _remaining_after_percents(self, percents: list[float]) -> float:
        """Multiplicative remaining fraction after sequential percents.

        ``Π(1 − pⱼ/100)`` — 30% then 20% → 0.56 remaining (0.44 off). The one
        place percents compound, shared by the per-line aggregation and each
        membership's own post-discount price.
        """
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
        """A membership's own post-discount price (minor units).

        Its plan ``base_price`` with its **own** already-extracted ``percents``
        and ``dollar_sum`` applied in ``DISCOUNT_APPLICATION_ORDER`` (percent
        then dollar): the percents compound (``_remaining_after_percents``), then
        the fixed dollars are subtracted. Floored at 0, rounded to integer cents.
        Percent-first is what lets these per-membership prices sum to the
        consolidated line total with no rescaling.
        """
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
        """Aggregate one consolidated line in one pass over its memberships.

        Returns ``(line_values, membership_amounts)`` from a **single** walk of each
        membership's discounts, so the line coupons and the per-membership figure can
        never disagree about a membership's discounts.

        ``line_values`` — at most one percent value and one dollar value. Percents
        compound **sequentially within a membership**
        (``eff = 1 − Π(1 − pⱼ/100)`` — 30% then 20% → 0.44, not 0.50), the
        per-membership effective fractions are **summed across the line** then
        divided by quantity (``line_percent = Σ effᵢ / qty × 100``); fixed dollars
        are **summed**. Percent and dollar stay separate values with **disjoint**
        ``contributing_ids`` (each discount is percent XOR dollar), so each
        value's resolved coupon is written back onto only its own rows.

        ``membership_amounts`` — ``item_id → that membership's own post-discount
        price`` (``_post_discount_amount`` on its plan ``price``), counting all of
        the membership's currently active discounts (the read already drops any
        past its ``end_date``). Covers **every** membership; an undiscounted one
        keeps its full plan price.
        """
        divisor = len(memberships) if memberships else 1
        effective_fraction = 0.0
        dollar_sum = 0
        percent_ids: list[UUID] = []
        dollar_ids: list[UUID] = []
        membership_amounts: dict[UUID, int] = {}

        for membership in memberships:
            # Collect this membership's discounts FIRST, for EVERY membership
            # (frozen included): a frozen membership's applied-discount rows still
            # need to reach the writeback — their ids go into the line's
            # contributing_ids so they get a coupon link + flip to `applied`.
            # Freeze doesn't make them useless; it only zeros the bill.
            mem_percents: list[float] = []
            mem_dollars = 0
            for discount in membership.discounts:
                if discount.percentage_off:
                    percent_ids.append(discount.applied_discount_id)
                    mem_percents.append(discount.percentage_off)
                if discount.dollar_off:
                    dollar_ids.append(discount.applied_discount_id)
                    mem_dollars += discount.dollar_off
            # The membership's OWN post-discount price is always its real
            # standalone price (plan minus its own discounts) — even when frozen.
            # Freeze zeros the BILL (via the line below), not the membership's own
            # price; the CRM surfaces the frozen status separately.
            membership_amounts[membership.item_id] = self._post_discount_amount(
                membership.price, mem_percents, mem_dollars
            )
            if membership.is_frozen:
                # FREEZE = a synthetic 100%-off on this membership's line unit: it
                # bills $0 but STAYS on the subscription (keeps its line id, stays
                # `applied`), so nothing assuming `applied ⇒ on Stripe with an
                # item id` breaks. Riding the percent ÷ quantity averaging below,
                # a consolidated line with k of N frozen bills only the (N − k)
                # active units. Its fixed-$ off is deliberately NOT added to the
                # line's dollar_sum — a flat $-off would leak onto the active
                # units on a shared line, and the 1.0 override already zeros this
                # unit.
                effective_fraction += 1.0
                continue
            effective_fraction += 1 - self._remaining_after_percents(mem_percents)
            dollar_sum += mem_dollars

        values: list[LineDiscountValue] = []
        line_percent = effective_fraction / divisor * 100
        if line_percent > 0:
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
