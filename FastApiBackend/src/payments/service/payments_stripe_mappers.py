import stripe

from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewLineItem,
    PaymentsInvoicePreviewResponse,
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
