from typing import Self

from pydantic import BaseModel, Field, model_validator

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)

# ── Invoice Payments (itemized) ─────────────────────────────────


class PaymentsInvoiceItemSpec(BaseModel):
    """One line on an invoice: a Stripe price XOR an ad-hoc amount.

    Exactly one of ``stripe_price_id`` / ``amount`` is set — a price line bills
    a catalog price, an amount line bills a raw cents amount (late fees,
    pro-shop). ``coupon_ids`` attach as **item-level** discounts (ordered
    dollar→percent) so each line is discounted independently. ``description`` is
    the line label (used mainly for amount lines).
    """

    stripe_price_id: str | None = None
    amount: int | None = Field(default=None, gt=0)
    description: str | None = None
    coupon_ids: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _exactly_one_source(self) -> Self:
        """A line bills a price XOR a raw amount — exactly one must be set."""
        if (self.stripe_price_id is None) == (self.amount is None):
            raise ValueError(
                "PaymentsInvoiceItemSpec must set exactly one of "
                "stripe_price_id / amount"
            )
        return self


class PaymentsInvoicePaymentCreateRequest(BaseModel):
    """Create and pay ONE invoice from a list of items.

    Each item is its own invoice line (price or amount) with its own item-level
    discounts. A single charge is just a one-item list — itemized is the norm.
    ``metadata`` is the invoice-level envelope (a ``BaseStripeMetadata``
    subclass — membership-one-time or ad-hoc); the service calls its
    ``to_stripe_metadata()``. ``currency`` applies to amount lines (price lines
    carry their own). ``description`` is the INVOICE-level description (the
    header line on the hosted invoice/receipt) — distinct from each item's
    line-level ``description``.
    """

    stripe_customer_id: str
    items: list[PaymentsInvoiceItemSpec]
    metadata: BaseStripeMetadata
    currency: str = "usd"
    description: str | None = None
    paid_out_of_band: bool = False
    idempotency_key: str


class PaymentsInvoicePaymentPreviewRequest(BaseModel):
    """Preview an itemized invoice without paying."""

    stripe_customer_id: str
    items: list[PaymentsInvoiceItemSpec]


class PaymentsInvoicePaymentResponse(BaseModel):
    """Stripe Invoice payment details.

    ``line_item_ids`` and ``line_amounts`` come back in the SAME ORDER as the
    request ``items`` so a caller can map each item to its Stripe line id (e.g. a
    membership → ``stripe_item_id``) and its **post-discount** charged amount in
    cents (e.g. a membership's ``total_price``).
    """

    stripe_invoice_id: str
    stripe_customer_id: str
    amount_paid: int
    currency: str
    status: str
    line_item_ids: list[str] = Field(default_factory=list)
    line_amounts: list[int] = Field(default_factory=list)
    metadata: dict[str, str] = {}


# ── Refunds ─────────────────────────────────────────────────────


class PaymentsRefundRequest(BaseModel):
    """Refund a PaymentIntent (full or partial)."""

    stripe_payment_intent_id: str
    amount: int | None = None
    idempotency_key: str


class PaymentsRefundResponse(BaseModel):
    """Stripe Refund details."""

    stripe_refund_id: str
    stripe_payment_intent_id: str
    amount: int
    status: str
