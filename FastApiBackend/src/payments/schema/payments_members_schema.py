from datetime import date

from pydantic import BaseModel, field_validator

from src.payments.schema.payments_enums import StripeResourceType

# ── Customer & Card ──────────────────────────────────────────────


class PaymentsCustomerCreateRequest(BaseModel):
    """Create a Stripe Customer with mandatory payment method."""

    name: str
    email: str | None = None
    phone: str | None = None
    payment_method_id: str
    metadata: dict[str, str] | None = None


class PaymentsCustomerUpdateRequest(BaseModel):
    """Update a Stripe Customer's details and payment method."""

    stripe_customer_id: str
    name: str
    email: str | None = None
    phone: str | None = None
    payment_method_id: str
    metadata: dict[str, str] | None = None


class PaymentsCustomerResponse(BaseModel):
    """Stripe Customer with default payment method card details."""

    stripe_customer_id: str
    stripe_payment_method_id: str
    name: str | None = None
    email: str | None = None
    phone: str | None = None
    card_brand: str | None = None
    card_last_four: str | None = None
    card_exp_month: int | None = None
    card_exp_year: int | None = None


# ── Subscription ────────────────────────────────────────────────


class SubscriptionItemDiscount(BaseModel):
    """A coupon reference for the Stripe discounts array."""

    coupon: str


class PaymentsSubscriptionDesiredItem(BaseModel):
    """Desired state of a single item in a subscription."""

    stripe_price_id: str
    stripe_item_id: str | None = None
    prorate: bool = True
    quantity: int = 1
    discounts: list[SubscriptionItemDiscount] = []


class PaymentsSubscriptionCreateRequest(BaseModel):
    """Declarative subscription update.

    Send the desired state — the backend diffs against the current
    state and adds, updates, or removes items automatically.

    If ``stripe_subscription_id`` is None, a new subscription is created.
    If provided, the existing subscription is reconciled to match.
    """

    stripe_customer_id: str
    items: list[PaymentsSubscriptionDesiredItem]
    subscription_discounts: list[SubscriptionItemDiscount] = []
    metadata: dict[str, str] | None = None

    @field_validator("items")
    @classmethod
    def items_not_empty(
        cls,
        v: list[PaymentsSubscriptionDesiredItem],
    ) -> list[PaymentsSubscriptionDesiredItem]:
        """A subscription must have at least one item."""
        if not v:
            raise ValueError("A subscription must have at least one item")
        return v


class PaymentsSubscriptionUpdateRequest(PaymentsSubscriptionCreateRequest):
    stripe_subscription_id: str


class PaymentsSubscriptionItemResponse(BaseModel):
    """One line item within a subscription."""

    stripe_subscription_item_id: str
    stripe_price_id: str
    quantity: int
    discounts: list[str] = []


# ── Subscription-Level Operations ───────────────────────────────


class PaymentsSubscriptionFreezeRequest(BaseModel):
    """Freeze (pause collection on) a subscription."""

    stripe_subscription_id: str
    freeze_end_date: date | None = None


class PaymentsSubscriptionUnfreezeRequest(BaseModel):
    """Resume (unfreeze) a paused subscription."""

    stripe_subscription_id: str


class PaymentsSubscriptionCancelRequest(BaseModel):
    """Cancel a subscription (immediately or at period end)."""

    stripe_subscription_id: str
    cancel_at_period_end: bool = False


class PaymentsSubscriptionResponse(BaseModel):
    """Stripe Subscription details with multiple items."""

    stripe_subscription_id: str
    stripe_customer_id: str
    items: list[PaymentsSubscriptionItemResponse]
    status: str
    current_period_start: int | None = None
    current_period_end: int | None = None
    cancel_at_period_end: bool = False
    discounts: list[str] = []
    metadata: dict[str, str] = {}


class PaymentsSubscriptionFreezeResponse(BaseModel):
    """Response after freezing/pausing a subscription."""

    stripe_subscription_id: str
    pause_collection_behavior: str
    resumes_at: int | None = None


# ── Batch Migration ─────────────────────────────────────────────


class PaymentsSubscriptionPriceMigrationRequest(BaseModel):
    """Migrate a list of subscriptions to a new price."""

    subscription_ids: list[str]
    old_stripe_price_id: str
    new_stripe_price_id: str
    proration_behavior: str = "none"


class PaymentsResourceNotFoundDetail(BaseModel):
    """A resource that was not found."""

    resource_id: str
    resource_type: StripeResourceType


class PaymentsSubscriptionPriceMigrationError(BaseModel):
    """Error for a single failed migration.

    ``not_found`` is set when the failure is a missing resource.
    ``stripe_error`` is set when the failure is an unexpected Stripe error.
    """

    subscription_id: str
    stripe_account_id: str
    not_found: PaymentsResourceNotFoundDetail | None = None
    stripe_error: str | None = None


class PaymentsSubscriptionPriceMigrationResponse(BaseModel):
    """Response after batch price migration."""

    migrated: list[str] = []
    errors: list[PaymentsSubscriptionPriceMigrationError] = []
