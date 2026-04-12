import logging

import stripe
from schema.membership_plan import PlanType
from stripe.params._price_create_params import (
    PriceCreateParams,
    PriceCreateParamsRecurring,
)
from stripe.params._price_update_params import PriceUpdateParams

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_price_schema import (
    PaymentsPriceCreateRequest,
    PaymentsPriceDeactivateRequest,
    PaymentsPriceResponse,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient

logger = logging.getLogger(__name__)


class PaymentsStripePriceService:
    """Stripe Price operations.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    # ── helpers ───────────────────────────────────────────────────

    def _map_price(self, price: stripe.Price) -> PaymentsPriceResponse:
        """Map a Stripe Price to our response schema."""
        recurring_interval = None
        recurring_interval_count = None
        if price.recurring:
            recurring_interval = price.recurring.interval
            recurring_interval_count = price.recurring.interval_count

        return PaymentsPriceResponse(
            stripe_price_id=price.id,
            stripe_product_id=price.product,
            unit_amount=price.unit_amount or 0,
            currency=price.currency,
            active=price.active,
            recurring_interval=recurring_interval,
            recurring_interval_count=recurring_interval_count,
        )

    # ── CRUD ─────────────────────────────────────────────────────

    async def create_price(
        self,
        request: PaymentsPriceCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Create a Stripe Price on a product.

        Recurring plans get recurring pricing; one_time and trial
        plans get one-time pricing.

        Args:
            request: Price details (product, amount, interval).
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Created price details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        params = PriceCreateParams(
            product=request.stripe_product_id,
            unit_amount=request.unit_amount,
            currency=request.currency,
        )
        if request.metadata:
            params["metadata"] = request.metadata
        if request.plan_type == PlanType.recurring:
            params["recurring"] = PriceCreateParamsRecurring(
                interval=request.recurring_interval.value,
                interval_count=request.recurring_interval_count,
            )

        price = await self._stripe.v1.prices.create_async(
            params=params,
            options=opts,
        )
        return self._map_price(price)

    async def deactivate_price(
        self,
        request: PaymentsPriceDeactivateRequest,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Archive (deactivate) a Stripe Price.

        Args:
            request: Price ID to deactivate.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Deactivated price details.
        """
        await self.get_price(request.stripe_price_id, stripe_account_id)

        opts = self._client.connect_opts(stripe_account_id)

        price = await self._stripe.v1.prices.update_async(
            request.stripe_price_id,
            params=PriceUpdateParams(active=False),
            options=opts,
        )
        return self._map_price(price)

    async def activate_price(
        self,
        price_id: str,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Reactivate a Stripe Price.

        Args:
            price_id: The Stripe price ID to reactivate.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Reactivated price details.
        """
        await self.get_price(price_id, stripe_account_id)

        opts = self._client.connect_opts(stripe_account_id)

        price = await self._stripe.v1.prices.update_async(
            price_id,
            params=PriceUpdateParams(active=True),
            options=opts,
        )
        return self._map_price(price)

    async def get_price(
        self,
        price_id: str,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Retrieve a Stripe Price.

        Args:
            price_id: The Stripe price ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Price details.

        Raises:
            PaymentsResourceNotFoundError: If the price does not exist.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            price = await self._stripe.v1.prices.retrieve_async(
                price_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Price {price_id} not found",
                resource_id=price_id,
                resource_type=StripeResourceType.price,
            ) from exc

        return self._map_price(price)

    async def validate_price_active(
        self,
        price_id: str,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Ensure a price and its product are active, reactivating if needed.

        Retrieves the price and its parent product. If either is
        inactive (archived), it is reactivated on Stripe — the gym
        owner is explicitly trying to use this resource.

        Args:
            price_id: The Stripe price ID.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Price details.

        Raises:
            PaymentsResourceNotFoundError: If the price or product
                does not exist or is deleted.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            price = await self._stripe.v1.prices.retrieve_async(
                price_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Price {price_id} not found",
                resource_id=price_id,
                resource_type=StripeResourceType.price,
            ) from exc

        if not price.active:
            price = await self._stripe.v1.prices.update_async(
                price_id,
                params=PriceUpdateParams(active=True),
                options=opts,
            )

        try:
            product = await self._stripe.v1.products.retrieve_async(
                price.product,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Product {price.product} not found",
                resource_id=price.product,
                resource_type=StripeResourceType.product,
            ) from exc

        if product.deleted:
            raise PaymentsResourceNotFoundError(
                f"Product {product.id} not found",
                resource_id=product.id,
                resource_type=StripeResourceType.product,
            )
        if not product.active:
            await self._stripe.v1.products.update_async(
                product.id,
                params={"active": True},
                options=opts,
            )

        return self._map_price(price)
