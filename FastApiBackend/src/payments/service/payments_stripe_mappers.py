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
            lines.append(
                PaymentsInvoicePreviewLineItem(
                    amount=line.amount,
                    description=line.description,
                    stripe_price_id=(line.price.id if line.price else None),
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
