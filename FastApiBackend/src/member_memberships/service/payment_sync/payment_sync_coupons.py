"""Deterministic find-or-create of Stripe coupons at sync time.

Coupons are computed at sync, not pre-baked on the preset. Each consolidated
line's effective value (a percent or a fixed dollar amount, per discount mode)
maps to exactly one Stripe coupon, identified by a **deterministic id** derived
from the value signature (``pct_<bps>_<mode>`` / ``amt_<cents>_<mode>``). Because
the id is a pure function of the value, find-or-create is idempotent and one
coupon per value is reused across every member on the gym's Connect account.

``once`` discounts map to a Stripe ``once`` coupon, ``ongoing`` to a Stripe
``forever`` coupon. Stripe has no native arbitrary end date — we enforce the
``end_date`` cutoff ourselves by dropping the applied discount once it passes
(in the read), so an ongoing coupon is always ``forever`` on Stripe.

Because a coupon's value is **immutable** on Stripe, a coupon that already exists
under a deterministic id is **validated** against the value before reuse: a
stored amount/duration that no longer matches (a stale or hand-edited coupon) is
deleted and recreated, so the id always resolves to a correctly-valued coupon.

This class owns only that **id scheme + validate-or-replace policy**. The actual
Stripe coupon I/O (find / create / delete) is delegated to
``PaymentsStripeDiscountService`` — the single payments-layer owner of the Stripe
SDK; nothing here touches Stripe directly.
"""

import logging

from schema.gym_discount import DiscountMode

from src.member_memberships.schema.payment_sync_schema import (
    LineDiscountValue,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountDeleteRequest,
    PaymentsDiscountResponse,
)
from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)

logger = logging.getLogger(__name__)

# Stripe percent_off accepts at most 2 decimal places; per-unit percents are
# summed then divided by quantity, so the line percent can carry fractions.
_PERCENT_DECIMALS = 2

_MODE_TO_STRIPE_DURATION: dict[DiscountMode, StripeCouponDuration] = {
    DiscountMode.once: StripeCouponDuration.once,
    DiscountMode.ongoing: StripeCouponDuration.forever,
}


class PaymentSyncCoupons:
    """Find-or-create deterministic Stripe coupons for consolidated lines."""

    def __init__(
        self,
        discount_service: PaymentsStripeDiscountService,
    ) -> None:
        self._discounts = discount_service

    @staticmethod
    def coupon_id(value: LineDiscountValue) -> str:
        """Deterministic coupon id for a line's effective discount value.

        ``pct_<bps>_<mode>`` for a percent (basis points, integer) or
        ``amt_<cents>_<mode>`` for a fixed dollar amount, so one coupon per
        distinct value+mode is reused on the Connect account.
        """
        if value.percentage_off is not None:
            bps = round(value.percentage_off * 100)
            return f"pct_{bps}_{value.discount_mode.value}"
        cents = int(value.dollar_off or 0)
        return f"amt_{cents}_{value.discount_mode.value}"

    async def find_or_create(
        self,
        value: LineDiscountValue,
        stripe_account_id: str,
    ) -> str:
        """Return the deterministic coupon id, creating it if absent or wrong.

        Finds the coupon by its deterministic id (via the discount service). If
        one exists, its stored amount + duration are **validated** against the
        value: a match is reused; a mismatch (a stale or hand-edited coupon —
        Stripe coupons are immutable, so the value can only be fixed by replacing
        it) is **deleted** so the correct one is recreated under the same id. The
        create is idempotent on the id, so a concurrent create of the same value
        is safe.

        Args:
            value: The line's effective discount value + mode.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            The coupon id now present (and correctly valued) on the account.
        """
        coupon_id = self.coupon_id(value)

        existing = await self._discounts.find_discount(
            coupon_id,
            stripe_account_id,
        )
        if existing is not None:
            if self._matches_value(existing, value):
                return coupon_id
            # Stale/corrupted coupon under this id — Stripe coupons are
            # immutable, so delete it and recreate with the correct value.
            logger.warning(
                "Coupon %s on %s has the wrong value; replacing it.",
                coupon_id,
                stripe_account_id,
            )
            await self._delete(coupon_id, stripe_account_id)

        created = await self._discounts.create_discount(
            self._build_create_request(coupon_id, value),
            stripe_account_id,
        )
        return created.stripe_coupon_id

    async def _delete(
        self,
        coupon_id: str,
        stripe_account_id: str,
    ) -> None:
        """Delete a coupon by id, ignoring an already-absent one."""
        try:
            await self._discounts.delete_discount(
                PaymentsDiscountDeleteRequest(stripe_coupon_id=coupon_id),
                stripe_account_id,
            )
        except PaymentsResourceNotFoundError:
            # Already gone (a concurrent replace deleted it) — fine.
            return

    @staticmethod
    def _matches_value(
        coupon: PaymentsDiscountResponse,
        value: LineDiscountValue,
    ) -> bool:
        """Whether an existing coupon's amount + duration match a value.

        Guards against reusing a stale/corrupted coupon: the deterministic id
        encodes the intended value, but the coupon object on Stripe could have
        drifted (hand-edited, or created by older math). Compares exactly the
        fields ``_build_create_request`` would set.
        """
        if coupon.duration != _MODE_TO_STRIPE_DURATION[value.discount_mode]:
            return False
        if value.percentage_off is not None:
            expected_percent = round(value.percentage_off, _PERCENT_DECIMALS)
            return coupon.percentage_off == expected_percent
        return coupon.amount_off == int(value.dollar_off or 0)

    @staticmethod
    def _build_create_request(
        coupon_id: str,
        value: LineDiscountValue,
    ) -> PaymentsDiscountCreateRequest:
        """Build the coupon-create request for a line value.

        ``once`` -> Stripe ``once`` duration; ``ongoing`` -> Stripe ``forever``
        duration (our end_date cutoff is enforced separately, in the read). The
        id is mirrored into the name so the dashboard shows the value signature.
        """
        duration = _MODE_TO_STRIPE_DURATION[value.discount_mode]
        if value.percentage_off is not None:
            return PaymentsDiscountCreateRequest(
                coupon_id=coupon_id,
                discount_name=coupon_id,
                duration=duration,
                percentage_off=round(value.percentage_off, _PERCENT_DECIMALS),
            )
        return PaymentsDiscountCreateRequest(
            coupon_id=coupon_id,
            discount_name=coupon_id,
            duration=duration,
            amount_off=int(value.dollar_off or 0),
            currency="usd",
        )
