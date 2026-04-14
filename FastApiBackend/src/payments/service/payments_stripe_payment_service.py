import logging

from stripe.params._invoice_create_params import InvoiceCreateParams
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
    InvoiceCreatePreviewParamsInvoiceItem,
)
from stripe.params._invoice_item_create_params import InvoiceItemCreateParams
from stripe.params._payment_intent_create_params import (
    PaymentIntentCreateParams,
)
from stripe.params._refund_create_params import RefundCreateParams

from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentResponse,
    PaymentsPaymentCreateRequest,
    PaymentsPaymentResponse,
    PaymentsRefundRequest,
    PaymentsRefundResponse,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_mappers import map_invoice_preview
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)

logger = logging.getLogger(__name__)


class PaymentsStripePaymentService:
    """Stripe one-time payment operations.

    Supports direct-amount charges via PaymentIntents
    and price-based charges via Invoices.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
        members_service: PaymentsStripeMembersService,
        price_service: PaymentsStripePriceService,
    ) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client
        self._members = members_service
        self._prices = price_service

    # ── Direct Amount Payments ───────────────────────────────────

    async def create_payment(
        self,
        request: PaymentsPaymentCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsPaymentResponse:
        """Create and confirm a one-time PaymentIntent.

        Uses the customer's default payment method with
        ``off_session=True`` for server-initiated charges.

        Args:
            request: Customer ID, amount, currency, optional metadata.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            PaymentIntent details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        customer = await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )

        # Resolve the default payment method for off-session charges.
        default_pm = None
        if customer.invoice_settings and customer.invoice_settings.default_payment_method:
            pm_ref = customer.invoice_settings.default_payment_method
            default_pm = pm_ref if isinstance(pm_ref, str) else pm_ref.id
        if not default_pm:
            raise ValueError(
                f"Customer {request.stripe_customer_id} has no default payment method"
            )

        pi = await self._stripe.v1.payment_intents.create_async(
            params=PaymentIntentCreateParams(
                customer=request.stripe_customer_id,
                payment_method=default_pm,
                amount=request.amount,
                currency=request.currency,
                confirm=True,
                off_session=True,
                metadata=request.metadata,
            ),
            options=opts,
        )

        return PaymentsPaymentResponse(
            stripe_payment_intent_id=pi.id,
            stripe_customer_id=pi.customer,
            amount=pi.amount,
            currency=pi.currency,
            status=pi.status,
            metadata=pi.metadata.to_dict() if pi.metadata else {},
        )

    # ── Price-Based Invoice Payments ─────────────────────────────

    async def create_invoice_payment(
        self,
        request: PaymentsInvoicePaymentCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePaymentResponse:
        """Create and pay an invoice from a Stripe Price.

        Creates an InvoiceItem referencing the price, then creates
        and pays the invoice. The price already knows the product,
        amount, and currency.

        Args:
            request: Customer ID, price ID, optional metadata.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Invoice payment details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )
        await self._prices.validate_price_active(
            request.stripe_price_id,
            stripe_account_id,
        )

        invoice = await self._stripe.v1.invoices.create_async(
            params=InvoiceCreateParams(
                customer=request.stripe_customer_id,
                metadata=request.metadata,
                auto_advance=False,
            ),
            options=opts,
        )

        await self._stripe.v1.invoice_items.create_async(
            params=InvoiceItemCreateParams(
                customer=request.stripe_customer_id,
                invoice=invoice.id,
                pricing={"price": request.stripe_price_id},
            ),
            options=opts,
        )

        invoice = await self._stripe.v1.invoices.finalize_invoice_async(
            invoice.id,
            options=opts,
        )

        # Zero-amount invoices are auto-marked as paid at finalization,
        # so calling pay_async again raises "Invoice is already paid".
        if invoice.status != "paid":
            invoice = await self._stripe.v1.invoices.pay_async(
                invoice.id,
                options=opts,
            )

        return PaymentsInvoicePaymentResponse(
            stripe_invoice_id=invoice.id,
            stripe_customer_id=invoice.customer,
            stripe_price_id=request.stripe_price_id,
            amount_paid=invoice.amount_paid,
            currency=invoice.currency,
            status=invoice.status,
            metadata=invoice.metadata.to_dict() if invoice.metadata else {},
        )

    # ── Invoice Preview ───────────────────────────────────────────

    async def preview_invoice_payment(
        self,
        request: PaymentsInvoicePaymentCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview a one-time invoice charge without paying.

        Same validation as ``create_invoice_payment`` but no invoice
        is created — uses Stripe's ``invoices.create_preview``.

        Args:
            request: Customer ID, price ID, optional metadata.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Invoice preview with amount due and line items.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )
        await self._prices.validate_price_active(
            request.stripe_price_id,
            stripe_account_id,
        )

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=InvoiceCreatePreviewParams(
                customer=request.stripe_customer_id,
                invoice_items=[
                    InvoiceCreatePreviewParamsInvoiceItem(
                        price=request.stripe_price_id,
                        quantity=1,
                    ),
                ],
            ),
            options=opts,
        )
        return map_invoice_preview(invoice)

    # ── Refunds ──────────────────────────────────────────────────

    async def refund_payment(
        self,
        request: PaymentsRefundRequest,
        stripe_account_id: str,
    ) -> PaymentsRefundResponse:
        """Refund a PaymentIntent (full or partial).

        Works for both direct-amount and invoice-based payments,
        since invoices create a PaymentIntent under the hood.

        If ``amount`` is None, a full refund is issued.

        Args:
            request: PaymentIntent ID and optional partial amount.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Refund details.
        """
        opts = self._client.connect_opts(stripe_account_id)

        params = RefundCreateParams(
            payment_intent=request.stripe_payment_intent_id,
        )
        if request.amount is not None:
            params["amount"] = request.amount

        refund = await self._stripe.v1.refunds.create_async(
            params=params,
            options=opts,
        )

        return PaymentsRefundResponse(
            stripe_refund_id=refund.id,
            stripe_payment_intent_id=request.stripe_payment_intent_id,
            amount=refund.amount,
            status=refund.status,
        )
