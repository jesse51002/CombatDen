"""Resolve each consolidated line's discount coupons + own the discount math."""

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


class PaymentSyncDiscounts:
    """Owns the discount math and resolves each line's coupons at build time.

    For each consolidated line (a price group of memberships) it aggregates the
    memberships' discounts into at most one value per mode — percents compound
    **sequentially within a membership** then average across the line (÷
    quantity), dollars sum — find-or-creates the deterministic coupon per value
    on the gym's Connect account, and orders them **dollar before percent** so
    Stripe applies them sequentially in that order (we do only the
    percentage-level math; Stripe sequences dollar→percent on the line).

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
          the builder to attach onto each consolidated line (dollar coupon
          first, then percent, so Stripe sequences dollar→percent).
        - ``links``: ``applied_discount_id → coupon_id`` for the real path to
          write back (a ``once`` value records its coupon — the consumption
          handle — on its rows; an ``ongoing`` value on its rows).

        A no-op (empty maps) when no line carries a discount.
        """
        coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]] = {}
        links: dict[UUID, str] = {}
        for price_id, memberships in groups.items():
            values = self._aggregate_line_values(memberships)
            if not values:
                continue
            # Dollar (`amount_off`) before percent (`percent_off`) so Stripe
            # sequences dollar→percent on the line.
            ordered_values = sorted(
                values,
                key=lambda v: v.percentage_off is not None,
            )
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
        )

    # ── Discount Math ───────────────────────────────────────────────

    def _aggregate_line_values(
        self,
        memberships: list[ActiveMembershipRow],
    ) -> list[LineDiscountValue]:
        """Aggregate one consolidated line's discounts into ≤1 value per mode.

        The line is a price group of ``memberships`` (quantity = how many). The
        memberships' discounts are already date-filtered by the read (expired /
        consumed ones excluded), so this is pure aggregation. For each discount
        mode (``once`` / ``ongoing``, kept separate — different Stripe durations):

        - **Percents** compound **sequentially within a membership**
          (``eff = 1 − Π(1 − pⱼ/100)`` — 30% then 20% → 0.44, not 0.50), and the
          per-membership effective fractions are **summed across the line** then
          divided by the line quantity: ``line_percent = (Σ effᵢ / qty) × 100``.
          A membership with no discount contributes 0, so a partly-discounted
          line averages correctly.
        - **Dollars** are **summed** across the line's memberships (a
          fixed-dollar coupon applies to the whole quantity-N line).

        Dollar vs percent are **not** combined here — they become separate
        coupons and Stripe applies them sequentially (dollar→percent) via the
        attach order. The percent value and the dollar value carry **disjoint**
        ``contributing_ids`` (each discount is percent XOR dollar), so each
        value's resolved coupon is written back onto only its own rows — a
        dollar-``once``'s presence handle is its own dollar coupon, never the
        percent coupon.
        """
        divisor = len(memberships) if memberships else 1
        values: list[LineDiscountValue] = []
        for mode in (DiscountMode.once, DiscountMode.ongoing):
            percent_ids: list[UUID] = []
            dollar_ids: list[UUID] = []
            effective_fraction = 0.0
            dollar_sum = 0
            for membership in memberships:
                member_percents: list[float] = []
                for discount in membership.discounts:
                    if discount.discount_mode != mode:
                        continue
                    if discount.percentage_off:
                        percent_ids.append(discount.applied_discount_id)
                        member_percents.append(discount.percentage_off)
                    if discount.dollar_off:
                        dollar_ids.append(discount.applied_discount_id)
                        dollar_sum += discount.dollar_off
                remaining = 1.0
                for percent in member_percents:
                    remaining *= 1 - percent / 100
                effective_fraction += 1 - remaining
            line_percent = effective_fraction / divisor * 100

            if line_percent > 0:
                values.append(
                    LineDiscountValue(
                        discount_mode=mode,
                        percentage_off=line_percent,
                        contributing_ids=percent_ids,
                    )
                )
            if dollar_sum > 0:
                values.append(
                    LineDiscountValue(
                        discount_mode=mode,
                        dollar_off=dollar_sum,
                        contributing_ids=dollar_ids,
                    )
                )
        return values
