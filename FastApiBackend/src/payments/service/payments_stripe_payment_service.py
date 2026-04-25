import logging

import stripe
from stripe.params._invoice_create_params import InvoiceCreateParams
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
    InvoiceCreatePreviewParamsInvoiceItem,
)
from stripe.params._invoice_item_create_params import InvoiceItemCreateParams
from stripe.params._invoice_list_params import InvoiceListParams
from stripe.params._invoice_pay_params import InvoicePayParams
from stripe.params._invoice_update_params import InvoiceUpdateParams
from stripe.params._refund_create_params import RefundCreateParams

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoicePaymentByAmountRequest,
    PaymentsInvoicePaymentByAmountResponse,
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentPreviewRequest,
    PaymentsInvoicePaymentResponse,
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

INVOICE_STATUS_OPEN = "open"
SUBSCRIPTION_OPEN_INVOICE_LIMIT = 1

logger = logging.getLogger(__name__)


class PaymentsStripePaymentService:
    """Stripe one-time payment operations.

    Supports direct-amount charges via PaymentIntents and invoice
    charges (price-based or ad-hoc-amount) via Invoices.

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

    # ── Price-Based Invoice Payments ─────────────────────────────

    async def create_invoice_payment(
        self,
        request: PaymentsInvoicePaymentCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePaymentResponse:
        """Create and pay an invoice from a Stripe Price."""
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        base_key = request.idempotency_key

        await self._members.retrieve_customer(
            request.stripe_customer_id,
            read_opts,
        )
        await self._prices.validate_price_active(
            request.stripe_price_id,
            stripe_account_id,
        )

        metadata = request.metadata.model_copy(
            update={"crm_paid_with_cash": True} if request.paid_out_of_band else {},
        )

        invoice = await self._stripe.v1.invoices.create_async(
            params=InvoiceCreateParams(
                customer=request.stripe_customer_id,
                metadata=metadata.to_stripe_metadata(),
                auto_advance=False,
            ),
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:invoice",
            ),
        )

        await self._stripe.v1.invoice_items.create_async(
            params=InvoiceItemCreateParams(
                customer=request.stripe_customer_id,
                invoice=invoice.id,
                pricing={"price": request.stripe_price_id},
            ),
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:invoice_item",
            ),
        )

        invoice = await self._stripe.v1.invoices.finalize_invoice_async(
            invoice.id,
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:finalize",
            ),
        )

        # Zero-amount invoices are auto-marked as paid at finalization,
        # so calling pay_async again raises "Invoice is already paid".
        if invoice.status != "paid":
            pay_params = InvoicePayParams()
            if request.paid_out_of_band:
                pay_params["paid_out_of_band"] = True
            invoice = await self._stripe.v1.invoices.pay_async(
                invoice.id,
                params=pay_params,
                options=self._client.connect_opts(
                    stripe_account_id,
                    idempotency_key=f"{base_key}:pay",
                ),
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

    # ── Ad-Hoc Amount Invoice Payments ───────────────────────────

    async def create_invoice_payment_by_amount(
        self,
        request: PaymentsInvoicePaymentByAmountRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePaymentByAmountResponse:
        """Create and pay an invoice for an ad-hoc amount.

        Unlike :meth:`create_invoice_payment`, no Stripe Price is used —
        the amount is set directly on an InvoiceItem. Used for one-off
        charges (late fees, pro-shop items, etc.). ``description`` is
        applied both to the invoice and the invoice line item so it
        appears as the line-item name on the Stripe invoice.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)
        base_key = request.idempotency_key

        await self._members.retrieve_customer(
            request.stripe_customer_id,
            read_opts,
        )

        metadata = request.metadata.model_copy(
            update={"crm_paid_with_cash": True} if request.paid_out_of_band else {},
        )

        invoice = await self._stripe.v1.invoices.create_async(
            params=InvoiceCreateParams(
                customer=request.stripe_customer_id,
                description=request.description,
                metadata=metadata.to_stripe_metadata(),
                auto_advance=False,
            ),
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:invoice",
            ),
        )

        await self._stripe.v1.invoice_items.create_async(
            params=InvoiceItemCreateParams(
                customer=request.stripe_customer_id,
                invoice=invoice.id,
                amount=request.amount,
                currency=request.currency,
                description=request.description,
            ),
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:invoice_item",
            ),
        )

        invoice = await self._stripe.v1.invoices.finalize_invoice_async(
            invoice.id,
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:finalize",
            ),
        )

        if invoice.status != "paid":
            pay_params = InvoicePayParams()
            if request.paid_out_of_band:
                pay_params["paid_out_of_band"] = True
            invoice = await self._stripe.v1.invoices.pay_async(
                invoice.id,
                params=pay_params,
                options=self._client.connect_opts(
                    stripe_account_id,
                    idempotency_key=f"{base_key}:pay",
                ),
            )

        return PaymentsInvoicePaymentByAmountResponse(
            stripe_invoice_id=invoice.id,
            stripe_customer_id=invoice.customer,
            amount_paid=invoice.amount_paid,
            currency=invoice.currency,
            status=invoice.status,
            metadata=invoice.metadata.to_dict() if invoice.metadata else {},
        )

    # ── Invoice Preview ───────────────────────────────────────────

    async def preview_invoice_payment(
        self,
        request: PaymentsInvoicePaymentPreviewRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview a one-time invoice charge without paying.

        Stateless preview, but ``validate_price_active`` may
        defensively reactivate an archived price.
        """
        opts = self._client.connect_opts_readonly(stripe_account_id)

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
        """Refund a PaymentIntent (full or partial)."""
        opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=request.idempotency_key
        )

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

    # ── Pay Out of Band ──────────────────────────────────────────

    async def pay_open_subscription_invoice_out_of_band(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
        *,
        idempotency_key: str,
    ) -> str:
        """Mark a subscription's currently-open invoice as paid via cash.

        Finds the single open invoice belonging to the subscription
        and calls ``invoices.pay`` with ``paid_out_of_band=True``.
        Stripe fires the normal ``invoice.paid`` webhook, which
        handles the CRM write.
        """
        read_opts = self._client.connect_opts_readonly(stripe_account_id)

        list_params = InvoiceListParams(
            subscription=stripe_subscription_id,
            status=INVOICE_STATUS_OPEN,
            limit=SUBSCRIPTION_OPEN_INVOICE_LIMIT,
        )
        try:
            invoice_list = await self._stripe.v1.invoices.list_async(
                params=list_params,
                options=read_opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Subscription {stripe_subscription_id} not found",
                resource_id=stripe_subscription_id,
                resource_type=StripeResourceType.subscription,
            ) from exc

        invoices = invoice_list.data or []
        if not invoices:
            raise ValueError(f"No open invoice for subscription {stripe_subscription_id}")

        invoice = invoices[0]

        # Stripe does not propagate subscription metadata to its
        # generated invoices, so we cannot round-trip this through
        # StripeSubscriptionMetadata — the invoice lacks the required
        # crm_user_id/gym_id. The webhook recovers crm_user_id for
        # subscription invoices via sub-item lookup; only the cash
        # flag needs to land on the invoice itself.
        existing = invoice.metadata.to_dict() if invoice.metadata else {}
        merged = {**existing, "crm_paid_with_cash": "true"}
        await self._stripe.v1.invoices.update_async(
            invoice.id,
            params=InvoiceUpdateParams(
                metadata=merged,
            ),
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{idempotency_key}:update",
            ),
        )

        pay_params = InvoicePayParams()
        pay_params["paid_out_of_band"] = True
        try:
            await self._stripe.v1.invoices.pay_async(
                invoice.id,
                params=pay_params,
                options=self._client.connect_opts(
                    stripe_account_id,
                    idempotency_key=f"{idempotency_key}:pay",
                ),
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Invoice {invoice.id} not found",
                resource_id=invoice.id,
                resource_type=StripeResourceType.invoice,
            ) from exc

        return invoice.id
