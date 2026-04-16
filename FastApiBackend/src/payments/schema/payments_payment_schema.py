from pydantic import BaseModel

# ── One-Time Payments (direct amount) ───────────────────────────


class PaymentsPaymentCreateRequest(BaseModel):
    """Create a one-time PaymentIntent with a specific amount."""

    stripe_customer_id: str
    amount: int
    currency: str = "usd"
    metadata: dict[str, str] | None = None


class PaymentsPaymentResponse(BaseModel):
    """Stripe PaymentIntent details."""

    stripe_payment_intent_id: str
    stripe_customer_id: str
    amount: int
    currency: str
    status: str
    metadata: dict[str, str] = {}


# ── Invoice Payments (price-based) ──────────────────────────────


class PaymentsInvoicePaymentCreateRequest(BaseModel):
    """Create a one-time invoice charge from a Stripe Price."""

    stripe_customer_id: str
    stripe_price_id: str
    metadata: dict[str, str] | None = None
    paid_out_of_band: bool = False


class PaymentsInvoicePaymentResponse(BaseModel):
    """Stripe Invoice payment details."""

    stripe_invoice_id: str
    stripe_customer_id: str
    stripe_price_id: str
    amount_paid: int
    currency: str
    status: str
    metadata: dict[str, str] = {}


# ── Refunds ─────────────────────────────────────────────────────


class PaymentsRefundRequest(BaseModel):
    """Refund a PaymentIntent (full or partial)."""

    stripe_payment_intent_id: str
    amount: int | None = None


class PaymentsRefundResponse(BaseModel):
    """Stripe Refund details."""

    stripe_refund_id: str
    stripe_payment_intent_id: str
    amount: int
    status: str
