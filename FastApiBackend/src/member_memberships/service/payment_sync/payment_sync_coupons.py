"""Deterministic find-or-create of Stripe coupons at sync time.

Coupons are computed at sync, not pre-baked on the preset. Each consolidated
line's effective value (a percent or a fixed dollar amount, per discount mode)
maps to exactly one Stripe coupon, identified by a **deterministic id** derived
from the value signature (``pct_<bps>_<mode>`` / ``amt_<cents>_<mode>``). Because
the id is a pure function of the value, find-or-create is idempotent and one
coupon per value is reused across every member on the gym's Connect account.

``once`` discounts map to a Stripe ``once`` coupon, ``ongoing`` to a Stripe
``forever`` coupon. Stripe has no native arbitrary end date — we enforce the
``end_date`` cutoff ourselves by dropping the snapshot once it passes (see the
sync's end_date exclusion), so an ongoing coupon is always ``forever`` on Stripe.
"""

import logging

import stripe
from schema.gym_discount import DiscountMode
from stripe.params._coupon_create_params import CouponCreateParams

from src.member_memberships.schema.payment_sync_schema import (
    LineDiscountValue,
)
from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.service.payments_stripe_client import PaymentsStripeClient

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

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

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
        """Return the deterministic coupon id, creating it if absent.

        Creation passes the deterministic id so a concurrent or repeat call
        for the same value collides on Stripe's side; the collision is caught
        and treated as "already exists" (idempotent).

        Args:
            value: The line's effective discount value + mode.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            The coupon id now present on the Connect account.
        """
        coupon_id = self.coupon_id(value)
        read_opts = self._client.connect_opts_readonly(stripe_account_id)

        existing = await self._retrieve(coupon_id, read_opts)
        if existing is not None:
            return coupon_id

        write_opts = self._client.connect_opts(stripe_account_id)
        params = self._build_create_params(coupon_id, value)
        try:
            created = await self._stripe.v1.coupons.create_async(
                params=params,
                options=write_opts,
            )
            return created.id
        except stripe.InvalidRequestError:
            # Lost a create race (id already taken) — the coupon now exists.
            return coupon_id

    async def _retrieve(
        self,
        coupon_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Coupon | None:
        """Retrieve a coupon by id, or None if it does not exist."""
        try:
            coupon = await self._stripe.v1.coupons.retrieve_async(
                coupon_id,
                options=opts,
            )
        except stripe.InvalidRequestError:
            return None
        if getattr(coupon, "deleted", False):
            return None
        return coupon

    @staticmethod
    def _build_create_params(
        coupon_id: str,
        value: LineDiscountValue,
    ) -> CouponCreateParams:
        """Build Stripe coupon-create params for a line value.

        ``once`` -> Stripe ``once`` duration; ``ongoing`` -> Stripe
        ``forever`` duration (our end_date cutoff is enforced separately).
        """
        duration = _MODE_TO_STRIPE_DURATION[value.discount_mode]
        params = CouponCreateParams(
            id=coupon_id,
            name=coupon_id,
            duration=duration.value,
        )
        if value.percentage_off is not None:
            params["percent_off"] = round(
                value.percentage_off,
                _PERCENT_DECIMALS,
            )
        else:
            params["amount_off"] = int(value.dollar_off or 0)
            params["currency"] = "usd"
        return params
