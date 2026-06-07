from pydantic import BaseModel, Field

from src.payments.schema.metadata.stripe_ad_hoc_invoice_metadata import (
    StripeAdHocInvoiceMetadata,
)
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)

# ── Invoice Payments (price-based) ──────────────────────────────


class PaymentsInvoicePaymentCreateRequest(BaseModel):
    """Create a one-time invoice charge from a Stripe Price."""

    stripe_customer_id: str
    stripe_price_id: str
    metadata: StripeMembershipOneTimeMetadata
    paid_out_of_band: bool = False
    idempotency_key: str


class PaymentsInvoicePaymentPreviewRequest(BaseModel):
    """Preview a one-time invoice charge from a Stripe Price."""

    stripe_customer_id: str
    stripe_price_id: str


class PaymentsInvoicePaymentResponse(BaseModel):
    """Stripe Invoice payment details."""

    stripe_invoice_id: str
    stripe_customer_id: str
    stripe_price_id: str
    amount_paid: int
    currency: str
    status: str
    metadata: dict[str, str] = {}


# ── Invoice Payments (ad-hoc amount, no price) ─────────────────


class PaymentsInvoicePaymentByAmountRequest(BaseModel):
    """Create a one-time invoice charge with an ad-hoc amount.

    Unlike :class:`PaymentsInvoicePaymentCreateRequest`, this does not
    reference a Stripe Price — the amount and description are supplied
    directly. Used for one-off charges (e.g. late fees, pro-shop items)
    that have no corresponding membership price.
    """

    stripe_customer_id: str
    amount: int = Field(..., gt=0)
    currency: str = "usd"
    description: str
    metadata: StripeAdHocInvoiceMetadata
    paid_out_of_band: bool = False
    idempotency_key: str


class PaymentsInvoicePaymentByAmountResponse(BaseModel):
    """Response for an ad-hoc-amount invoice payment."""

    stripe_invoice_id: str
    stripe_customer_id: str
    amount_paid: int
    currency: str
    status: str
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
