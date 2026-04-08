import logging

import stripe
from stripe.params._coupon_create_params import CouponCreateParams
from stripe.params._coupon_update_params import CouponUpdateParams

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountCreateRequest,
    PaymentsDiscountResponse,
    PaymentsDiscountUpdateRequest,
)
from src.payments.schema.payments_enums import StripeCouponDuration, StripeResourceType
from src.payments.service.payments_stripe_client import PaymentsStripeClient

logger = logging.getLogger(__name__)


class PaymentsStripeDiscountService:
    """Stripe Coupon CRUD operations.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    # ── helpers ───────────────────────────────────────────────────

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
            metadata=dict(coupon.metadata) if coupon.metadata else {},
        )

    async def retrieve_discount(
        self,
        coupon_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Coupon:
        """Retrieve a Stripe Coupon, raising if not found.

        Args:
            coupon_id: The Stripe coupon ID.
            opts: Stripe Connect request options.

        Returns:
            The Stripe Coupon object.

        Raises:
            PaymentsResourceNotFoundError: If the coupon does not exist.
        """
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

        if coupon.deleted:
            raise PaymentsResourceNotFoundError(
                f"Coupon {coupon_id} not found",
                resource_id=coupon_id,
                resource_type=StripeResourceType.coupon,
            )
        return coupon

    # ── CRUD ─────────────────────────────────────────────────────

    async def create_discount(
        self,
        request: PaymentsDiscountCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsDiscountResponse:
        """Create a Stripe Coupon.

        Args:
            request: Coupon details (percentage_off or amount_off).
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Created coupon details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        coupon = await self._stripe.v1.coupons.create_async(
            params=CouponCreateParams(
                name=request.discount_name,
                duration=request.duration.value,
                percent_off=request.percentage_off,
                amount_off=request.amount_off,
                currency=request.currency,
                duration_in_months=request.duration_in_months,
                metadata=request.metadata,
            ),
            options=opts,
        )
        return self._map_coupon(coupon)

    async def update_discount(
        self,
        request: PaymentsDiscountUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsDiscountResponse:
        """Update a Stripe Coupon (name and metadata only).

        Verifies the coupon exists before updating.

        Args:
            request: Coupon ID with new name and optional metadata.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Updated coupon details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self.retrieve_discount(request.stripe_coupon_id, opts)

        coupon = await self._stripe.v1.coupons.update_async(
            request.stripe_coupon_id,
            params=CouponUpdateParams(
                name=request.discount_name,
                metadata=request.metadata,
            ),
            options=opts,
        )
        return self._map_coupon(coupon)

    async def delete_discount(
        self,
        coupon_id: str,
        stripe_account_id: str,
    ) -> None:
        """Delete a Stripe Coupon.

        Args:
            coupon_id: The Stripe coupon ID to delete.
            stripe_account_id: The gym's Stripe Connect account ID.

        Raises:
            PaymentsResourceNotFoundError: If the coupon does not exist.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            await self._stripe.v1.coupons.delete_async(
                coupon_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Coupon {coupon_id} not found",
                resource_id=coupon_id,
                resource_type=StripeResourceType.coupon,
            ) from exc
