from pydantic import BaseModel

# ── Invoice preview ─────────────────────────────────────────────


class PreviewInvoiceLine(BaseModel):
    """A single line item from an invoice preview.

    ``amount`` is Stripe's raw line amount (untouched); ``discounted_amount``
    is the post-discount value (``subtotal − Σ discount_amounts``). The line
    also carries ``stripe_subscription_item_id`` (None for one-off items) and
    ``is_proration`` so a consumer that wants only the steady-state recurring
    view can filter — the mapper itself returns every line.
    """

    amount: int
    discounted_amount: int
    description: str | None = None
    stripe_price_id: str | None = None
    quantity: int | None = None
    stripe_subscription_item_id: str | None = None
    is_proration: bool = False


class PreviewInvoice(BaseModel):
    """Preview of what an invoice would look like without charging.

    The one preview shape, produced by ``map_preview_invoice`` and returned
    (directly, wrapped in ``DueNowVsRecurringPreview``, or filtered to the
    recurring lines for the upcoming-invoice read) by every preview surface.
    """

    amount_due: int
    subtotal: int
    total: int
    currency: str
    lines: list[PreviewInvoiceLine] = []


# ── Due-now vs Recurring Preview ────────────────────────────────


class DueNowVsRecurringPreview(BaseModel):
    """A preview split into what is charged now vs. what recurs.

    Both halves are ordinary invoice previews assembled by the caller:
    ``due_now`` is the immediate invoice (``None`` when nothing is
    charged now), ``recurring`` is the steady-state per-cycle invoice
    (the ``proration_behavior=none`` preview).
    """

    due_now: PreviewInvoice | None = None
    recurring: PreviewInvoice | None = None


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
