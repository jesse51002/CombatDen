"""Resolve each consolidated line's discount coupons + own the discount math."""

from enum import IntEnum
from uuid import UUID

from schema.gym_discount import DiscountMode

from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    LineDiscountValue,
    ResolvedDiscounts,
)
from src.member_memberships.service.payment_sync.payment_sync_coupons import (
    PaymentSyncCoupons,
)
from src.payments.schema.payments_members_schema import (
    SubscriptionItemDiscount,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
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
    memberships' discounts into at most one value per mode — percents compound
    **sequentially within a membership** then average across the line (÷
    quantity), dollars sum — find-or-creates the deterministic coupon per value
    on the gym's Connect account, and orders them **percent before dollar**
    (``DISCOUNT_APPLICATION_ORDER``) so Stripe applies them sequentially in that
    order (we do only the percentage-level math; Stripe sequences percent→dollar
    on the line).

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
        self._coupons = PaymentSyncCoupons(discount_service)

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
          write back (a ``once`` value records its coupon — the consumption
          handle — on its rows; an ``ongoing`` value on its rows).
        - ``membership_amounts``: each membership's ``item_id`` → its own
          post-discount price (plan price with its ongoing discounts always, and
          its once discounts only once it is on Stripe), for **every** membership.

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
                coupon_id = await self._coupons.find_or_create(
                    value,
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

        ``line_values`` — at most one value per mode (``once`` / ``ongoing``,
        kept separate for their different Stripe durations). Per mode: percents
        compound **sequentially within a membership**
        (``eff = 1 − Π(1 − pⱼ/100)`` — 30% then 20% → 0.44, not 0.50), the
        per-membership effective fractions are **summed across the line** then
        divided by quantity (``line_percent = Σ effᵢ / qty × 100``); fixed dollars
        are **summed**. Percent and dollar stay separate values with **disjoint**
        ``contributing_ids`` (each discount is percent XOR dollar), so each
        value's resolved coupon is written back onto only its own rows.

        ``membership_amounts`` — ``item_id → that membership's own post-discount
        price`` (``_post_discount_amount`` on its plan ``price``). It always
        counts the membership's **ongoing** discounts; it counts a ``once``
        discount only when the membership is **already on Stripe** (its
        ``stripe_item_id`` is set), as that once then applies to a future invoice
        — a not-yet-synced membership (no ``stripe_item_id``) excludes its once.
        Covers **every** membership; an undiscounted one keeps its full plan
        price.
        """
        divisor = len(memberships) if memberships else 1
        modes = (DiscountMode.once, DiscountMode.ongoing)
        effective_fraction = {mode: 0.0 for mode in modes}
        dollar_sum = {mode: 0 for mode in modes}
        percent_ids: dict[DiscountMode, list[UUID]] = {m: [] for m in modes}
        dollar_ids: dict[DiscountMode, list[UUID]] = {m: [] for m in modes}
        membership_amounts: dict[UUID, int] = {}

        for membership in memberships:
            mode_percents: dict[DiscountMode, list[float]] = {
                m: [] for m in modes
            }
            # The per-membership figure counts ongoing discounts always; it counts a
            # once discount only when the membership is already on Stripe (its
            # once then applies to a future invoice). A not-yet-synced membership
            # (no stripe_item_id) excludes its once.
            count_once = membership.stripe_item_id is not None
            amount_percents: list[float] = []
            amount_dollars = 0
            for discount in membership.discounts:
                mode = discount.discount_mode
                in_amount = mode is DiscountMode.ongoing or count_once
                if discount.percentage_off:
                    percent_ids[mode].append(discount.applied_discount_id)
                    mode_percents[mode].append(discount.percentage_off)
                    if in_amount:
                        amount_percents.append(discount.percentage_off)
                if discount.dollar_off:
                    dollar_ids[mode].append(discount.applied_discount_id)
                    dollar_sum[mode] += discount.dollar_off
                    if in_amount:
                        amount_dollars += discount.dollar_off
            for mode in modes:
                effective_fraction[mode] += (
                    1 - self._remaining_after_percents(mode_percents[mode])
                )
            membership_amounts[membership.item_id] = self._post_discount_amount(
                membership.price, amount_percents, amount_dollars
            )

        values: list[LineDiscountValue] = []
        for mode in modes:
            line_percent = effective_fraction[mode] / divisor * 100
            if line_percent > 0:
                values.append(
                    LineDiscountValue(
                        discount_mode=mode,
                        percentage_off=line_percent,
                        contributing_ids=percent_ids[mode],
                    )
                )
            if dollar_sum[mode] > 0:
                values.append(
                    LineDiscountValue(
                        discount_mode=mode,
                        dollar_off=dollar_sum[mode],
                        contributing_ids=dollar_ids[mode],
                    )
                )
        return values, membership_amounts
