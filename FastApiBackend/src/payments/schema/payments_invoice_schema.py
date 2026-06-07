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


# ── Upcoming Invoice ────────────────────────────────────────────


class UpcomingInvoiceLine(BaseModel):
    """A single post-discount line item on an upcoming subscription invoice."""

    stripe_subscription_item_id: str
    stripe_price_id: str | None = None
    quantity: int
    amount: int  # post-discount line total in cents


class UpcomingInvoiceResponse(BaseModel):
    """Preview of the next invoice for an existing subscription."""

    amount_due: int
    subtotal: int
    total: int
    currency: str
    lines: list[UpcomingInvoiceLine] = []


# ── Due-now vs Recurring Preview ────────────────────────────────


class DueNowVsRecurringPreview(BaseModel):
    """A preview split into what is charged now vs. what recurs.

    Both halves are ordinary invoice previews assembled by the caller:
    ``due_now`` is the immediate invoice (``None`` when nothing is
    charged now), ``recurring`` is the steady-state per-cycle invoice
    (the ``proration_behavior=none`` preview).
    """

    due_now: PaymentsInvoicePreviewResponse | None = None
    recurring: PaymentsInvoicePreviewResponse | None = None


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
