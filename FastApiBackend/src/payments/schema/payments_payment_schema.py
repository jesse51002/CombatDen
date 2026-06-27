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
    the line label (used mainly for amount lines). ``quantity`` multiplies a
    PRICE line's unit amount (a stacked one_time / trial pack billed as one line
    of N units); it only applies to price lines, since an ``amount`` line's
    amount is already the line total, so quantity must stay 1 there.
    """

    stripe_price_id: str | None = None
    amount: int | None = Field(default=None, gt=0)
    description: str | None = None
    quantity: int = Field(default=1, gt=0)
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

    @model_validator(mode="after")
    def _quantity_only_on_price(self) -> Self:
        """quantity > 1 is meaningful only for a price line (it multiplies the
        unit amount); an amount line's amount is already the total."""
        if self.amount is not None and self.quantity != 1:
            raise ValueError(
                "PaymentsInvoiceItemSpec quantity must be 1 for an amount line "
                "(quantity multiplies a price line's unit amount only)"
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

    ``payment_method_id`` charges a SPECIFIC one-off card (entered at checkout)
    instead of the customer's default: the service attaches it, pays with it,
    then detaches it — never touching the saved default. (Saving a card as the
    default is a separate, up-front ``update_customer`` step, not this path.)
    It is mutually exclusive with ``paid_out_of_band``.
    """

    stripe_customer_id: str
    items: list[PaymentsInvoiceItemSpec]
    metadata: BaseStripeMetadata
    currency: str = "usd"
    description: str | None = None
    paid_out_of_band: bool = False
    payment_method_id: str | None = None
    idempotency_key: str

    @model_validator(mode="after")
    def _pm_not_with_cash(self) -> Self:
        """A specific card and an out-of-band (cash) settle are exclusive."""
        if self.payment_method_id is not None and self.paid_out_of_band:
            raise ValueError(
                "payment_method_id cannot be combined with "
                "paid_out_of_band (a cash settle charges no card)"
            )
        return self


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
    """Refund a charge (full or partial).

    Refunds by the original ``stripe_charge_id`` (``ch_…``) — the identifier the
    CRM stores on ``member_charges`` and the one the ``refund.*`` webhook keys
    on — so no PaymentIntent lookup is needed. ``amount`` is positive minor
    units; ``None`` refunds the full remaining balance.
    """

    stripe_charge_id: str
    amount: int | None = None
    idempotency_key: str


class PaymentsRefundResponse(BaseModel):
    """Stripe Refund details.

    Carries everything the caller needs to record the refund as a
    ``member_charges`` row without a second Stripe read: the refund id, the
    original charge, the minor-units actually refunded, the Stripe refund
    ``status`` (``succeeded`` for a card refund, ``pending`` for an async one),
    the currency, and the Stripe ``created`` unix timestamp.
    """

    stripe_refund_id: str
    stripe_charge_id: str
    amount: int
    status: str
    currency: str
    created: int
