import logging

import stripe
from stripe.params._coupon_create_params import CouponCreateParams

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsCouponValue,
    PaymentsDiscountDeleteRequest,
    PaymentsDiscountResponse,
)
from src.payments.schema.payments_enums import (
    StripeCouponDuration,
    StripeResourceType,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient

logger = logging.getLogger(__name__)

# Stripe percent_off accepts at most 2 decimal places; a line percent can carry
# fractions (per-unit percents summed then divided by quantity).
_PERCENT_DECIMALS = 2

# Every discount coupon is a Stripe `forever` coupon. A discount's lifetime is
# enforced by OUR resolved `end_date` cutoff (the sync read drops anything past
# it), never by Stripe coupon duration — so a `forever` coupon is never consumed
# by appearing on an invoice and a mid-cycle proration can't burn it.
_COUPON_DURATION = StripeCouponDuration.forever


class PaymentsStripeDiscountService:
    """Stripe Coupon I/O + the deterministic value→coupon find-or-create.

    The single place coupon create/find/delete happens (no service outside the
    payments layer touches the Stripe SDK for coupons) AND the single owner of
    the **deterministic-id + validate-or-replace** policy
    (``find_or_create_for_value``). Both billing modes of the sync — recurring
    and one-time (via ``PaymentSyncDiscounts``, fed per-membership groups for the
    one-time path) — resolve a discount value into a coupon through here, one
    shared value→coupon mechanism.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    def _map_coupon(
        self,
        coupon: stripe.Coupon,
    ) -> PaymentsDiscountResponse:
        """Map a Stripe Coupon to our response schema."""
        return PaymentsDiscountResponse(
            stripe_coupon_id=coupon.id,
            name=coupon.name or "",
            percentage_off=coupon.percent_off,
            amount_off=coupon.amount_off,
            currency=coupon.currency,
            duration=StripeCouponDuration(coupon.duration),
            duration_in_months=coupon.duration_in_months,
            valid=coupon.valid,
            metadata=coupon.metadata.to_dict() if coupon.metadata else {},
        )

    async def retrieve_discount(
        self,
        coupon_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Coupon:
        """Retrieve a Stripe Coupon, raising if not found."""
        try:
            coupon = await self._stripe.v1.coupons.retrieve_async(
                coupon_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Coupon {coupon_id} not found",
                resource_id=coupon_id,
                resource_type=StripeResourceType.coupon,
            ) from exc

        if getattr(coupon, "deleted", False):
            raise PaymentsResourceNotFoundError(
                f"Coupon {coupon_id} not found",
                resource_id=coupon_id,
                resource_type=StripeResourceType.coupon,
            )
        return coupon

    async def find_discount(
        self,
        coupon_id: str,
        stripe_account_id: str,
    ) -> PaymentsDiscountResponse | None:
        """Retrieve a coupon by id, or ``None`` if it is absent / deleted.

        The non-raising, account-based counterpart to ``retrieve_discount`` —
        what a find-or-create caller needs to decide reuse-vs-create.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        try:
            coupon = await self._stripe.v1.coupons.retrieve_async(
                coupon_id,
                options=read_opts,
            )
        except stripe.InvalidRequestError:
            return None
        if getattr(coupon, "deleted", False):
            return None
        return self._map_coupon(coupon)

    async def _create_coupon(
        self,
        coupon_id: str,
        value: PaymentsCouponValue,
        stripe_account_id: str,
    ) -> str:
        """Create the deterministic coupon for a value; return its id.

        The only coupon-create path (the deterministic find-or-create owns it).
        Idempotent on the id: a create race (the id was taken by a concurrent
        create of the same value) is caught and the existing coupon's id is
        returned. The coupon is always Stripe ``forever`` — a discount's lifetime
        is enforced by our resolved ``end_date`` cutoff in the read, not by Stripe
        duration. The id is mirrored into the coupon name so the dashboard shows
        the value signature.
        """
        params = CouponCreateParams(
            id=coupon_id,
            name=coupon_id,
            duration=_COUPON_DURATION.value,
        )
        if value.percentage_off is not None:
            params["percent_off"] = round(value.percentage_off, _PERCENT_DECIMALS)
        else:
            params["amount_off"] = int(value.dollar_off or 0)
            params["currency"] = "usd"

        write_opts = self._client.connect_opts(stripe_account_id)
        try:
            coupon = await self._stripe.v1.coupons.create_async(
                params=params,
                options=write_opts,
            )
        except stripe.InvalidRequestError:
            # Lost a create race (id already taken) — fetch the existing coupon.
            read_opts = self._client.connect_opts_readonly(stripe_account_id)
            coupon = await self._stripe.v1.coupons.retrieve_async(
                coupon_id,
                options=read_opts,
            )
        return coupon.id

    async def delete_discount(
        self,
        request: PaymentsDiscountDeleteRequest,
        stripe_account_id: str,
    ) -> None:
        """Delete a Stripe Coupon.

        Raises:
            PaymentsResourceNotFoundError: If the coupon does not exist.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            await self._stripe.v1.coupons.delete_async(
                request.stripe_coupon_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Coupon {request.stripe_coupon_id} not found",
                resource_id=request.stripe_coupon_id,
                resource_type=StripeResourceType.coupon,
            ) from exc

    # ── Deterministic value→coupon find-or-create ────────────────

    @staticmethod
    def coupon_id_for_value(value: PaymentsCouponValue) -> str:
        """Deterministic coupon id for a discount value.

        ``pct_<bps>`` (basis points, integer) for a percent or ``amt_<cents>``
        for a fixed dollar amount, so one ``forever`` coupon per distinct value
        is reused on the Connect account.
        """
        if value.percentage_off is not None:
            bps = round(value.percentage_off * 100)
            return f"pct_{bps}"
        cents = int(value.dollar_off or 0)
        return f"amt_{cents}"

    async def find_or_create_for_value(
        self,
        value: PaymentsCouponValue,
        stripe_account_id: str,
    ) -> str:
        """Return the deterministic coupon id for a value, creating/repairing it.

        The id is a pure function of the value, so this is idempotent and one
        coupon per value is reused across the gym's Connect account. An existing
        coupon is **validated** against the value (Stripe coupons are immutable);
        a mismatch (stale / hand-edited) is deleted and recreated under the same
        id. The create is itself idempotent on the id (a concurrent create of the
        same value is caught). The single value→coupon mechanism shared by the
        recurring sync and one-time membership discounting.
        """
        coupon_id = self.coupon_id_for_value(value)

        existing = await self.find_discount(coupon_id, stripe_account_id)
        if existing is not None:
            if self._matches_value(existing, value):
                return coupon_id
            logger.warning(
                "Coupon %s on %s has the wrong value; replacing it.",
                coupon_id,
                stripe_account_id,
            )
            await self._delete_ignoring_absent(coupon_id, stripe_account_id)

        return await self._create_coupon(coupon_id, value, stripe_account_id)

    async def _delete_ignoring_absent(
        self,
        coupon_id: str,
        stripe_account_id: str,
    ) -> None:
        """Delete a coupon by id, ignoring an already-absent one."""
        try:
            await self.delete_discount(
                PaymentsDiscountDeleteRequest(stripe_coupon_id=coupon_id),
                stripe_account_id,
            )
        except PaymentsResourceNotFoundError:
            # Already gone (a concurrent replace deleted it) — fine.
            return

    @staticmethod
    def _matches_value(
        coupon: PaymentsDiscountResponse,
        value: PaymentsCouponValue,
    ) -> bool:
        """Whether an existing coupon's amount + duration match a value.

        Guards against reusing a stale/corrupted coupon: the deterministic id
        encodes the intended value, but the coupon object could have drifted.
        Every coupon is ``forever`` (lifetime is our end_date cutoff, not Stripe
        duration); a drifted duration is treated as a mismatch and replaced.
        """
        if coupon.duration != _COUPON_DURATION:
            return False
        if value.percentage_off is not None:
            expected_percent = round(value.percentage_off, _PERCENT_DECIMALS)
            return coupon.percentage_off == expected_percent
        return coupon.amount_off == int(value.dollar_off or 0)
