import logging

import stripe
from stripe.params._product_create_params import ProductCreateParams
from stripe.params._product_update_params import ProductUpdateParams

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipDeactivateRequest,
    PaymentsMembershipPriceItem,
    PaymentsMembershipResponse,
    PaymentsMembershipUpdateRequest,
)
from src.payments.schema.payments_price_schema import (
    PaymentsPriceCreateRequest,
    PaymentsPriceDeactivateRequest,
    PaymentsPriceResponse,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)

logger = logging.getLogger(__name__)


class PaymentsStripeMembershipService:
    """Stripe Product + Price CRUD operations.

    Represents membership plans as Stripe Products with associated Prices.
    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
        price_service: PaymentsStripePriceService,
    ) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client
        self._price_service = price_service

    # ── helpers ───────────────────────────────────────────────────

    async def retrieve_product(
        self,
        product_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Product:
        """Retrieve a Stripe Product, raising if not found.

        Args:
            product_id: The Stripe product ID.
            opts: Stripe Connect request options.

        Returns:
            The Stripe Product object.

        Raises:
            PaymentsResourceNotFoundError: If the product does not exist.
        """
        try:
            product = await self._stripe.v1.products.retrieve_async(
                product_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Product {product_id} not found",
                resource_id=product_id,
                resource_type=StripeResourceType.product,
            ) from exc

        if product.deleted:
            raise PaymentsResourceNotFoundError(
                f"Product {product_id} not found",
                resource_id=product_id,
                resource_type=StripeResourceType.product,
            )
        return product

    @staticmethod
    def _map_price(price: stripe.Price) -> PaymentsPriceResponse:
        """Map a Stripe Price to our price response schema."""
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

    def _map_product(
        self,
        product: stripe.Product,
        prices: list[stripe.Price],
    ) -> PaymentsMembershipResponse:
        """Map Stripe Product + Prices to our response schema."""
        return PaymentsMembershipResponse(
            stripe_product_id=product.id,
            active=product.active,
            name=product.name,
            prices=[self._map_price(p) for p in prices],
            metadata=dict(product.metadata) if product.metadata else {},
        )

    async def _list_prices(
        self,
        product_id: str,
        opts: stripe.RequestOptions,
    ) -> list[stripe.Price]:
        """List all prices for a product."""
        result = await self._stripe.v1.prices.list_async(
            params={"product": product_id},
            options=opts,
        )
        return list(result.data)

    async def _create_price_from_item(
        self,
        item: PaymentsMembershipPriceItem,
        product_id: str,
        stripe_account_id: str,
    ) -> PaymentsPriceResponse:
        """Create a Stripe Price from a price item."""
        return await self._price_service.create_price(
            PaymentsPriceCreateRequest(
                stripe_product_id=product_id,
                unit_amount=item.unit_amount,
                plan_type=item.plan_type,
                recurring_interval=item.recurring_interval,
                recurring_interval_count=item.recurring_interval_count,
            ),
            stripe_account_id,
        )

    # ── CRUD ─────────────────────────────────────────────────────

    async def create_membership(
        self,
        request: PaymentsMembershipCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsMembershipResponse:
        """Create a Stripe Product with one or more Prices.

        Args:
            request: Plan details with a list of prices.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Created product and price details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        product = await self._stripe.v1.products.create_async(
            params=ProductCreateParams(
                name=request.plan_name,
                metadata=request.metadata,
            ),
            options=opts,
        )

        default_price_id: str | None = None
        for item in request.prices:
            price_resp = await self._create_price_from_item(item, product.id, stripe_account_id)
            if item.is_default:
                default_price_id = price_resp.stripe_price_id

        if default_price_id:
            product = await self._stripe.v1.products.update_async(
                product.id,
                params=ProductUpdateParams(
                    default_price=default_price_id,
                ),
                options=opts,
            )

        prices = await self._list_prices(product.id, opts)
        return self._map_product(product, prices)

    async def update_membership(
        self,
        request: PaymentsMembershipUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsMembershipResponse:
        """Update a Stripe Product and reconcile its Prices.

        For each price in the request:
        - Existing (has stripe_price_id): update active status if changed.
        - New (no stripe_price_id): create a new Stripe Price.

        Any existing active prices not in the request list are deactivated.

        Args:
            request: Product ID, updated plan details, and price list.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Updated product and price details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self.retrieve_product(request.stripe_product_id, opts)
        existing_prices = await self._list_prices(request.stripe_product_id, opts)
        existing_by_id = {p.id: p for p in existing_prices}

        incoming_ids: set[str] = set()
        default_price_id: str | None = None

        for item in request.prices:
            if item.stripe_price_id:
                incoming_ids.add(item.stripe_price_id)
                existing = existing_by_id.get(item.stripe_price_id)
                if existing and existing.active != item.active:
                    if item.active:
                        await self._price_service.activate_price(
                            item.stripe_price_id, stripe_account_id
                        )
                    else:
                        await self._price_service.deactivate_price(
                            PaymentsPriceDeactivateRequest(
                                stripe_price_id=item.stripe_price_id,
                            ),
                            stripe_account_id,
                        )
                if item.is_default:
                    default_price_id = item.stripe_price_id
            else:
                price_resp = await self._create_price_from_item(
                    item,
                    request.stripe_product_id,
                    stripe_account_id,
                )
                incoming_ids.add(price_resp.stripe_price_id)
                if item.is_default:
                    default_price_id = price_resp.stripe_price_id

        for price in existing_prices:
            if price.id not in incoming_ids and price.active:
                logger.warning(
                    "Deactivating price %s on product %s — not present in update request",
                    price.id,
                    request.stripe_product_id,
                )
                await self._price_service.deactivate_price(
                    PaymentsPriceDeactivateRequest(
                        stripe_price_id=price.id,
                    ),
                    stripe_account_id,
                )

        update_params = ProductUpdateParams(
            name=request.plan_name,
            metadata=request.metadata,
            active=True,
        )
        if default_price_id:
            update_params["default_price"] = default_price_id

        product = await self._stripe.v1.products.update_async(
            request.stripe_product_id,
            params=update_params,
            options=opts,
        )

        prices = await self._list_prices(product.id, opts)
        return self._map_product(product, prices)

    async def deactivate_membership(
        self,
        request: PaymentsMembershipDeactivateRequest,
        stripe_account_id: str,
    ) -> PaymentsMembershipResponse:
        """Deactivate (archive) a Stripe Product.

        Sets the product's ``active`` flag to False. This does NOT
        cancel existing subscriptions.

        Args:
            request: Product ID to deactivate.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Deactivated product details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self.retrieve_product(request.stripe_product_id, opts)

        product = await self._stripe.v1.products.update_async(
            request.stripe_product_id,
            params=ProductUpdateParams(active=False),
            options=opts,
        )

        prices = await self._list_prices(product.id, opts)
        return self._map_product(product, prices)
