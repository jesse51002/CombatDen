import logging

import stripe
from stripe.params._invoice_create_params import InvoiceCreateParams
from stripe.params._invoice_create_preview_params import (
    InvoiceCreatePreviewParams,
    InvoiceCreatePreviewParamsInvoiceItem,
    InvoiceCreatePreviewParamsInvoiceItemDiscount,
)
from stripe.params._invoice_item_create_params import (
    InvoiceItemCreateParams,
    InvoiceItemCreateParamsDiscount,
)
from stripe.params._invoice_list_params import InvoiceListParams
from stripe.params._invoice_pay_params import InvoicePayParams
from stripe.params._invoice_update_params import InvoiceUpdateParams
from stripe.params._refund_create_params import RefundCreateParams

from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
    PaymentsStripeError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    PreviewInvoice,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentPreviewRequest,
    PaymentsInvoicePaymentResponse,
    PaymentsRefundRequest,
    PaymentsRefundResponse,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_mappers import (
    map_preview_invoice,
    post_discount_amount,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)

INVOICE_STATUS_OPEN = "open"
SUBSCRIPTION_OPEN_INVOICE_LIMIT = 1

logger = logging.getLogger(__name__)


class PaymentsStripePaymentService:
    """Stripe one-time payment operations.

    Invoice charges are **itemized**: one invoice with a list of items, each a
    Stripe price or an ad-hoc amount, each with its own item-level discounts. A
    single charge is just a one-item list. Plus PaymentIntent refunds and the
    out-of-band pay of a subscription's open invoice.

    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
        members_service: PaymentsStripeMembersService,
    ) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client
        self._members = members_service

    # ── Itemized Invoice Payments ────────────────────────────────

    async def create_invoice_payment(
        self,
        request: PaymentsInvoicePaymentCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePaymentResponse:
        """Create and pay ONE invoice from a list of items.

        Each item becomes its own invoice line (a Stripe price or an ad-hoc
        amount) with its own item-level discount coupons. The returned
        ``line_item_ids`` are in the same order as ``request.items`` so a caller
        can map each item to its Stripe line id.
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

        invoice_params = InvoiceCreateParams(
            customer=request.stripe_customer_id,
            metadata=metadata.to_stripe_metadata(),
            auto_advance=False,
        )
        if request.description is not None:
            invoice_params["description"] = request.description
        invoice = await self._stripe.v1.invoices.create_async(
            params=invoice_params,
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:invoice",
            ),
        )

        invoice_item_ids = await self._create_items(
            request,
            invoice.id,
            stripe_account_id,
        )

        invoice = await self._stripe.v1.invoices.finalize_invoice_async(
            invoice.id,
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:finalize",
            ),
        )

        # Zero-amount invoices are auto-marked paid at finalization, so paying
        # again raises "Invoice is already paid".
        if invoice.status != "paid":
            invoice = await self._pay_invoice(
                invoice.id,
                request,
                stripe_account_id,
            )

        ordered_lines = self._order_lines(invoice, invoice_item_ids)
        return PaymentsInvoicePaymentResponse(
            stripe_invoice_id=invoice.id,
            stripe_customer_id=invoice.customer,
            amount_paid=invoice.amount_paid,
            currency=invoice.currency,
            status=invoice.status,
            line_item_ids=[line_id for line_id, _ in ordered_lines],
            line_amounts=[amount for _, amount in ordered_lines],
            metadata=invoice.metadata.to_dict() if invoice.metadata else {},
        )

    async def _pay_invoice(
        self,
        invoice_id: str,
        request: PaymentsInvoicePaymentCreateRequest,
        stripe_account_id: str,
    ) -> stripe.Invoice:
        """Pay a finalized invoice — cash, a one-off card, or the default.

        A one-off card (``request.payment_method_id``) must belong to the
        customer before Stripe will charge it, so we attach → pay → (on
        success) detach. The detach runs ONLY after a successful pay — a
        declined pay leaves the card attached but non-default so a retry can
        reuse it (a detached method can never be re-attached) — and is
        best-effort: the invoice is already paid, so a detach failure must not
        surface as a charge failure.
        """
        base_key = request.idempotency_key
        pay_params = InvoicePayParams()
        if request.paid_out_of_band:
            pay_params["paid_out_of_band"] = True

        if request.payment_method_id is not None:
            await self._members.attach_payment_method(
                request.payment_method_id,
                request.stripe_customer_id,
                stripe_account_id,
                idempotency_key=f"{base_key}:attach",
            )
            pay_params["payment_method"] = request.payment_method_id

        invoice = await self._stripe.v1.invoices.pay_async(
            invoice_id,
            params=pay_params,
            options=self._client.connect_opts(
                stripe_account_id,
                idempotency_key=f"{base_key}:pay",
            ),
        )

        if request.payment_method_id is not None:
            await self._detach_after_pay(
                request.payment_method_id,
                stripe_account_id,
                idempotency_key=f"{base_key}:detach",
            )

        return invoice

    async def _detach_after_pay(
        self,
        payment_method_id: str,
        stripe_account_id: str,
        *,
        idempotency_key: str,
    ) -> None:
        """Best-effort detach of a one-off card after a successful pay.

        The invoice is already paid, so a detach failure is logged and
        swallowed — raising would wrongly signal a charge failure and a caller
        could un-bill a billed invoice.
        """
        try:
            await self._members.detach_payment_method(
                payment_method_id,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )
        except Exception:
            # ANY failure here (Stripe error, network timeout, unexpected
            # None) must stay swallowed — the invoice is already paid, so
            # raising would wrongly read as a charge failure and a caller
            # could un-bill a billed invoice.
            logger.warning(
                "Failed to detach one-off payment method %s after a "
                "successful charge; it remains attached (non-default).",
                payment_method_id,
                exc_info=True,
            )

    async def _create_items(
        self,
        request: PaymentsInvoicePaymentCreateRequest,
        invoice_id: str,
        stripe_account_id: str,
    ) -> list[str]:
        """Create one InvoiceItem per request item (price or amount, with
        item-level discounts); return their ids in request order."""
        base_key = request.idempotency_key
        invoice_item_ids: list[str] = []
        for index, item in enumerate(request.items):
            params = InvoiceItemCreateParams(
                customer=request.stripe_customer_id,
                invoice=invoice_id,
            )
            if item.stripe_price_id is not None:
                params["pricing"] = {"price": item.stripe_price_id}
            else:
                params["amount"] = item.amount
                params["currency"] = request.currency
            if item.description is not None:
                params["description"] = item.description
            if item.coupon_ids:
                params["discounts"] = [
                    InvoiceItemCreateParamsDiscount(coupon=coupon_id)
                    for coupon_id in item.coupon_ids
                ]
            created = await self._stripe.v1.invoice_items.create_async(
                params=params,
                options=self._client.connect_opts(
                    stripe_account_id,
                    idempotency_key=f"{base_key}:invoice_item:{index}",
                ),
            )
            invoice_item_ids.append(created.id)
        return invoice_item_ids

    @staticmethod
    def _order_lines(
        invoice: stripe.Invoice,
        invoice_item_ids: list[str],
    ) -> list[tuple[str, int]]:
        """Map finalized invoice lines back to the InvoiceItems that created
        them, returning ``(line id, post-discount amount)`` in
        ``invoice_item_ids`` order.

        Each line references its source InvoiceItem at
        ``line.parent.invoice_item_details.invoice_item`` (dahlia); the amount is
        the line's net (post item-level discount) charge in cents. Raises if an
        item has no matching line (e.g. the default 10-line page truncated — an
        itemized invoice we build is far smaller).
        """
        line_by_item: dict[str, stripe.InvoiceLineItem] = {}
        for line in invoice.lines.data:
            parent = getattr(line, "parent", None)
            details = getattr(parent, "invoice_item_details", None)
            invoice_item = getattr(details, "invoice_item", None)
            if invoice_item:
                line_by_item[invoice_item] = line
        ordered: list[tuple[str, int]] = []
        for invoice_item_id in invoice_item_ids:
            line = line_by_item.get(invoice_item_id)
            if line is None:
                raise PaymentsStripeError(
                    f"No invoice line found for invoice item {invoice_item_id}"
                )
            ordered.append((line.id, post_discount_amount(line)))
        return ordered

    # ── Invoice Preview ───────────────────────────────────────────

    async def preview_invoice_payment(
        self,
        request: PaymentsInvoicePaymentPreviewRequest,
        stripe_account_id: str,
    ) -> PreviewInvoice:
        """Preview an itemized invoice without paying."""
        opts = self._client.connect_opts_readonly(stripe_account_id)

        await self._members.retrieve_customer(
            request.stripe_customer_id,
            opts,
        )

        invoice = await self._stripe.v1.invoices.create_preview_async(
            params=InvoiceCreatePreviewParams(
                customer=request.stripe_customer_id,
                invoice_items=[self._preview_item(item) for item in request.items],
            ),
            options=opts,
        )
        return map_preview_invoice(invoice)

    @staticmethod
    def _preview_item(
        item: PaymentsInvoiceItemSpec,
    ) -> InvoiceCreatePreviewParamsInvoiceItem:
        """Build one preview invoice-item (price or amount) with item-level
        discounts."""
        preview_item = InvoiceCreatePreviewParamsInvoiceItem(quantity=1)
        if item.stripe_price_id is not None:
            preview_item["price"] = item.stripe_price_id
        else:
            preview_item["amount"] = item.amount
        if item.coupon_ids:
            preview_item["discounts"] = [
                InvoiceCreatePreviewParamsInvoiceItemDiscount(coupon=coupon_id)
                for coupon_id in item.coupon_ids
            ]
        return preview_item

    # ── Refunds ──────────────────────────────────────────────────

    async def refund_payment(
        self,
        request: PaymentsRefundRequest,
        stripe_account_id: str,
    ) -> PaymentsRefundResponse:
        """Refund a charge (full or partial).

        Refunds by the original charge id (``ch_…``) — what the CRM stores and
        what the ``refund.*`` webhook keys on — so no PaymentIntent lookup is
        needed. The response carries the refund's ``status`` / ``currency`` /
        ``created`` so the caller can record it without a second Stripe read.
        """
        opts = self._client.connect_opts(
            stripe_account_id, idempotency_key=request.idempotency_key
        )

        params = RefundCreateParams(
            charge=request.stripe_charge_id,
        )
        if request.amount is not None:
            params["amount"] = request.amount

        refund = await self._stripe.v1.refunds.create_async(
            params=params,
            options=opts,
        )

        return PaymentsRefundResponse(
            stripe_refund_id=refund.id,
            stripe_charge_id=request.stripe_charge_id,
            amount=refund.amount,
            status=refund.status,
            currency=refund.currency,
            created=refund.created,
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
        # member_id/gym_id. The webhook recovers member_id for
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
