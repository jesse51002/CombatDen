import logging

import stripe
from stripe.params._customer_create_params import (
    CustomerCreateParams,
    CustomerCreateParamsInvoiceSettings,
)
from stripe.params._customer_update_params import (
    CustomerUpdateParams,
    CustomerUpdateParamsInvoiceSettings,
)
from stripe.params._invoice_list_params import InvoiceListParams
from stripe.params._payment_method_attach_params import (
    PaymentMethodAttachParams,
)

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
    PaymentsCustomerResponse,
    PaymentsCustomerUpdateRequest,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient

logger = logging.getLogger(__name__)


class PaymentsStripeMembersService:
    """Stripe Customer and PaymentMethod operations.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    # ── helpers ───────────────────────────────────────────────────

    def _map_customer_response(
        self,
        customer: stripe.Customer,
        pm: stripe.PaymentMethod | None = None,
    ) -> PaymentsCustomerResponse:
        """Map a Stripe Customer + optional PaymentMethod to our response schema."""
        return PaymentsCustomerResponse(
            stripe_customer_id=customer.id,
            stripe_payment_method_id=pm.id if pm else None,
            name=customer.name,
            email=customer.email,
            phone=customer.phone,
            card_brand=pm.card.brand if pm and pm.card else None,
            card_last_four=pm.card.last4 if pm and pm.card else None,
            card_exp_month=pm.card.exp_month if pm and pm.card else None,
            card_exp_year=pm.card.exp_year if pm and pm.card else None,
        )

    async def retrieve_customer(
        self,
        customer_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Customer:
        """Retrieve a Stripe Customer, raising if not found or deleted."""
        try:
            customer = await self._stripe.v1.customers.retrieve_async(
                customer_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Customer {customer_id} not found",
                resource_id=customer_id,
                resource_type=StripeResourceType.customer,
            ) from exc

        if getattr(customer, "deleted", False):
            raise PaymentsResourceNotFoundError(
                f"Customer {customer_id} not found",
                resource_id=customer_id,
                resource_type=StripeResourceType.customer,
            )
        return customer

    # ── Customer ─────────────────────────────────────────────────

    async def create_customer(
        self,
        request: PaymentsCustomerCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsCustomerResponse:
        """Create a Stripe Customer, optionally with a payment method.

        If ``payment_method_id`` is provided, attaches it as the
        default. Otherwise creates a customer with name/email only.

        Args:
            request: Customer details with optional payment_method_id.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Customer response with card details (if PM was provided).
        """
        opts = self._client.connect_opts(stripe_account_id)

        params = CustomerCreateParams(
            name=request.name,
            email=request.email,
            phone=request.phone,
            metadata=request.metadata,
        )

        if request.payment_method_id:
            params["payment_method"] = request.payment_method_id
            params["invoice_settings"] = CustomerCreateParamsInvoiceSettings(
                default_payment_method=request.payment_method_id,
            )

        customer = await self._stripe.v1.customers.create_async(
            params=params,
            options=opts,
        )

        pm = None
        if request.payment_method_id:
            pm = await self._stripe.v1.payment_methods.retrieve_async(
                request.payment_method_id,
                options=opts,
            )

        return self._map_customer_response(customer, pm)

    async def update_customer(
        self,
        request: PaymentsCustomerUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsCustomerResponse:
        """Update a Stripe Customer's details and swap payment method.

        Verifies the customer exists, attaches the new payment method,
        updates customer details, sets new PM as default, and detaches
        the old payment method.

        Args:
            request: Customer ID, updated details, and new payment_method_id.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Updated customer response with card details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        customer = await self.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )

        old_pm_id = None
        if customer.invoice_settings and customer.invoice_settings.default_payment_method:
            old_pm_id = customer.invoice_settings.default_payment_method

        await self._stripe.v1.payment_methods.attach_async(
            request.payment_method_id,
            params=PaymentMethodAttachParams(
                customer=request.stripe_customer_id,
            ),
            options=opts,
        )

        customer = await self._stripe.v1.customers.update_async(
            request.stripe_customer_id,
            params=CustomerUpdateParams(
                name=request.name,
                email=request.email,
                phone=request.phone,
                metadata=request.metadata,
                invoice_settings=CustomerUpdateParamsInvoiceSettings(
                    default_payment_method=request.payment_method_id,
                ),
            ),
            options=opts,
        )

        if old_pm_id:
            await self._stripe.v1.payment_methods.detach_async(
                old_pm_id,
                options=opts,
            )

        pm = await self._stripe.v1.payment_methods.retrieve_async(
            request.payment_method_id,
            options=opts,
        )
        return self._map_customer_response(customer, pm)

    # ── Unlink ───────────────────────────────────────────────────

    async def unlink_customer_card(
        self,
        stripe_customer_id: str,
        stripe_account_id: str,
    ) -> None:
        """Detach the default payment method from a Stripe customer.

        Retrieves the customer, detaches the default payment method
        if one exists, and clears the default_payment_method on
        invoice_settings.

        Gracefully handles the case where the customer is already
        deleted in Stripe (no-op).

        Args:
            stripe_customer_id: The Stripe customer ID.
            stripe_account_id: The gym's Stripe Connect account ID.
        """
        opts = self._client.connect_opts(stripe_account_id)

        try:
            customer = await self.retrieve_customer(
                stripe_customer_id,
                opts,
            )
        except PaymentsResourceNotFoundError:
            return

        pm_id = None
        if customer.invoice_settings and customer.invoice_settings.default_payment_method:
            pm_id = customer.invoice_settings.default_payment_method

        if pm_id:
            await self._stripe.v1.customers.update_async(
                stripe_customer_id,
                params=CustomerUpdateParams(
                    invoice_settings=CustomerUpdateParamsInvoiceSettings(
                        default_payment_method="",
                    ),
                ),
                options=opts,
            )
            await self._stripe.v1.payment_methods.detach_async(
                pm_id,
                options=opts,
            )

    # ── Invoices ─────────────────────────────────────────────────

    async def list_invoices(
        self,
        stripe_customer_id: str,
        stripe_account_id: str,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List invoices for a customer.

        Args:
            stripe_customer_id: The Stripe customer ID.
            stripe_account_id: The gym's Stripe Connect account ID.
            limit: Max invoices to return (1-100, default 10).
            starting_after: Cursor for pagination (invoice ID).

        Returns:
            List of invoice details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self.retrieve_customer(stripe_customer_id, opts)

        params = InvoiceListParams(
            customer=stripe_customer_id,
            limit=limit,
        )
        if starting_after:
            params["starting_after"] = starting_after

        result = await self._stripe.v1.invoices.list_async(
            params=params,
            options=opts,
        )

        return [
            PaymentsInvoiceResponse(
                stripe_invoice_id=inv.id,
                stripe_subscription_id=(
                    inv.subscription
                    if isinstance(inv.subscription, str)
                    else (inv.subscription.id if inv.subscription else None)
                ),
                amount_due=inv.amount_due,
                amount_paid=inv.amount_paid,
                amount_remaining=inv.amount_remaining,
                currency=inv.currency,
                status=inv.status,
                created=inv.created,
                hosted_invoice_url=inv.hosted_invoice_url,
                invoice_pdf=inv.invoice_pdf,
            )
            for inv in result.data
        ]
