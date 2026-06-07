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


def _post_discount_amount(line: stripe.InvoiceLineItem) -> int:
    """Return the post-discount amount for an invoice line item.

    Computed explicitly as ``subtotal - sum(discount_amounts)``
    instead of trusting ``line.amount``. Stripe's field semantics:

    * ``line.subtotal`` — pre-discount, pre-tax line amount.
    * ``line.discount_amounts[].amount`` — the portion of each
      applied discount that landed on this line. Subscription-level
      discounts (what this codebase uses via ``subscription.discounts``)
      are distributed into these per-line entries by Stripe.

    Doing the math ourselves makes the intent obvious and avoids
    relying on the ambiguous ``line.amount`` docstring.
    """
    subtotal = getattr(line, "subtotal", None)
    if subtotal is None:
        # Older API responses may not expose subtotal; fall back to
        # amount, which for line-level discounts is already net.
        subtotal = line.amount
    discount_total = 0
    discount_amounts = getattr(line, "discount_amounts", None) or []
    for da in discount_amounts:
        discount_total += getattr(da, "amount", 0) or 0
    return subtotal - discount_total


def _is_proration(line: stripe.InvoiceLineItem) -> bool:
    """Return True if this line represents a mid-cycle proration.

    Newer Stripe API versions expose the ``proration`` flag under
    ``line.parent.subscription_item_details`` or
    ``line.parent.invoice_item_details`` rather than on the line
    directly. Check both, plus the legacy top-level attribute as a
    safety net.
    """
    parent = getattr(line, "parent", None)
    if parent:
        sid = getattr(parent, "subscription_item_details", None)
        if sid and getattr(sid, "proration", False):
            return True
        iid = getattr(parent, "invoice_item_details", None)
        if iid and getattr(iid, "proration", False):
            return True
    return bool(getattr(line, "proration", False))


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
    item) are included — one-off invoice items are ignored. Mid-cycle
    proration lines (``line.proration is True``) are also skipped so
    the result reflects the steady-state recurring cost, not one-time
    adjustments that inflate the next invoice after an add/change.

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
            if _is_proration(line):
                continue
            si_id = _extract_subscription_item_id(line)
            if not si_id:
                continue
            quantity = line.quantity or 1
            lines.append(
                UpcomingInvoiceLine(
                    stripe_subscription_item_id=si_id,
                    stripe_price_id=_extract_price_id(line),
                    quantity=quantity,
                    amount=_post_discount_amount(line),
                )
            )

    return UpcomingInvoiceResponse(
        amount_due=invoice.amount_due,
        subtotal=invoice.subtotal,
        total=invoice.total,
        currency=invoice.currency,
        lines=lines,
    )
