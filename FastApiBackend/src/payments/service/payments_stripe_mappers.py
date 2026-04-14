import stripe

from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewLineItem,
    PaymentsInvoicePreviewResponse,
    UpcomingInvoiceLine,
    UpcomingInvoiceResponse,
)


def map_invoice_preview(
    invoice: stripe.Invoice,
) -> PaymentsInvoicePreviewResponse:
    """Map a Stripe Invoice preview to our response schema.

    Shared by subscription and payment preview methods.

    Args:
        invoice: Stripe Invoice object from ``create_preview``.

    Returns:
        Flattened invoice preview with line items.
    """
    lines: list[PaymentsInvoicePreviewLineItem] = []
    if invoice.lines and invoice.lines.data:
        for line in invoice.lines.data:
            # Resolve price ID from either legacy ``price`` or new ``pricing``.
            price_id = None
            if hasattr(line, "pricing") and line.pricing:
                pd = getattr(line.pricing, "price_details", None)
                if pd:
                    price_ref = pd.price
                    price_id = price_ref if isinstance(price_ref, str) else price_ref.id
            if not price_id and hasattr(line, "price") and line.price:
                price_id = line.price if isinstance(line.price, str) else line.price.id
            lines.append(
                PaymentsInvoicePreviewLineItem(
                    amount=line.amount,
                    description=line.description,
                    stripe_price_id=price_id,
                    quantity=line.quantity,
                )
            )

    return PaymentsInvoicePreviewResponse(
        amount_due=invoice.amount_due,
        subtotal=invoice.subtotal,
        total=invoice.total,
        currency=invoice.currency,
        lines=lines,
    )


def _extract_price_id(line: stripe.InvoiceLineItem) -> str | None:
    """Resolve a price ID from either legacy ``price`` or new ``pricing``."""
    if hasattr(line, "pricing") and line.pricing:
        pd = getattr(line.pricing, "price_details", None)
        if pd:
            price_ref = pd.price
            return price_ref if isinstance(price_ref, str) else price_ref.id
    if hasattr(line, "price") and line.price:
        return line.price if isinstance(line.price, str) else line.price.id
    return None


def _extract_subscription_item_id(
    line: stripe.InvoiceLineItem,
) -> str | None:
    """Resolve the subscription item ID from either legacy or ``parent``.

    Newer Stripe API versions expose ``subscription_item`` via
    ``line.parent.subscription_item_details.subscription_item``.
    Older versions expose it directly as ``line.subscription_item``.
    """
    parent = getattr(line, "parent", None)
    if parent:
        details = getattr(parent, "subscription_item_details", None)
        if details:
            si_ref = getattr(details, "subscription_item", None)
            if si_ref:
                return si_ref if isinstance(si_ref, str) else si_ref.id
    legacy = getattr(line, "subscription_item", None)
    if legacy:
        return legacy if isinstance(legacy, str) else legacy.id
    return None


def map_upcoming_invoice(
    invoice: stripe.Invoice,
) -> UpcomingInvoiceResponse:
    """Map a Stripe upcoming/preview invoice to the upcoming-invoice schema.

    Only recurring subscription lines (those tied to a subscription
    item) are included — one-off invoice items are ignored.

    Args:
        invoice: Stripe Invoice object from ``create_preview_async``
            using ``subscription=<sub_id>``.

    Returns:
        Upcoming invoice with per-line post-discount totals, keyed by
        ``stripe_subscription_item_id``.
    """
    lines: list[UpcomingInvoiceLine] = []
    if invoice.lines and invoice.lines.data:
        for line in invoice.lines.data:
            si_id = _extract_subscription_item_id(line)
            if not si_id:
                continue
            quantity = line.quantity or 1
            lines.append(
                UpcomingInvoiceLine(
                    stripe_subscription_item_id=si_id,
                    stripe_price_id=_extract_price_id(line),
                    quantity=quantity,
                    amount=line.amount,
                )
            )

    return UpcomingInvoiceResponse(
        amount_due=invoice.amount_due,
        subtotal=invoice.subtotal,
        total=invoice.total,
        currency=invoice.currency,
        lines=lines,
    )
