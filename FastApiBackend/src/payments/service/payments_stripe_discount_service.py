import logging

import stripe
from stripe.params._coupon_create_params import CouponCreateParams

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountDeleteRequest,
    PaymentsDiscountResponse,
)
from src.payments.schema.payments_enums import (
    StripeCouponDuration,
    StripeResourceType,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient

logger = logging.getLogger(__name__)


class PaymentsStripeDiscountService:
    """Stripe Coupon I/O — the single place coupon create/find/delete happens.

    All methods accept ``stripe_account_id`` for Stripe Connect. No service
    outside the payments layer should touch the Stripe SDK for coupons; the
    payment-sync engine's value-derived coupons (``PaymentSyncCoupons``) go
    through here.
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

    async def create_discount(
        self,
        request: PaymentsDiscountCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsDiscountResponse:
        """Create a Stripe Coupon under the caller-supplied id.

        Idempotent on the deterministic id: a create race (the id was taken by a
        concurrent create of the same value) is caught and the existing coupon is
        returned, so find-or-create stays safe under concurrency.
        """
        write_opts = self._client.connect_opts(stripe_account_id)
        params = CouponCreateParams(
            id=request.coupon_id,
            name=request.discount_name,
            duration=request.duration.value,
        )
        if request.duration_in_months is not None:
            params["duration_in_months"] = request.duration_in_months
        if request.percentage_off is not None:
            params["percent_off"] = request.percentage_off
        else:
            params["amount_off"] = int(request.amount_off or 0)
            params["currency"] = request.currency

        try:
            coupon = await self._stripe.v1.coupons.create_async(
                params=params,
                options=write_opts,
            )
        except stripe.InvalidRequestError:
            # Lost a create race (id already taken) — return the existing coupon.
            read_opts = self._client.connect_opts_readonly(stripe_account_id)
            coupon = await self._stripe.v1.coupons.retrieve_async(
                request.coupon_id,
                options=read_opts,
            )
        return self._map_coupon(coupon)

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
