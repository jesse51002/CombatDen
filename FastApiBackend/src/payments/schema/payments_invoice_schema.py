from pydantic import BaseModel

# ── Invoice Preview ─────────────────────────────────────────────


class PaymentsInvoicePreviewLineItem(BaseModel):
    """A single line item from an invoice preview."""

    amount: int
    description: str | None = None
    stripe_price_id: str | None = None
    quantity: int | None = None


class PaymentsInvoicePreviewResponse(BaseModel):
    """Preview of what an invoice would look like without charging."""

    amount_due: int
    subtotal: int
    total: int
    currency: str
    lines: list[PaymentsInvoicePreviewLineItem] = []


# ── Invoice List ────────────────────────────────────────────────


class PaymentsInvoiceResponse(BaseModel):
    """A finalized Stripe Invoice."""

    stripe_invoice_id: str
    stripe_subscription_id: str | None = None
    amount_due: int
    amount_paid: int
    amount_remaining: int
    currency: str
    status: str | None = None
    created: int
    hosted_invoice_url: str | None = None
    invoice_pdf: str | None = None
