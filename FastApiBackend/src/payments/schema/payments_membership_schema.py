from pydantic import BaseModel, model_validator
from schema.membership_plan import DurationUnit, PlanType

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_price_schema import PaymentsPriceResponse


class PaymentsMembershipPriceItem(BaseModel):
    """A price entry for create/update membership requests.

    For new prices, all pricing fields are required.
    For existing prices (stripe_price_id set), only active matters
    since Stripe prices are immutable.
    """

    stripe_price_id: str | None = None
    unit_amount: int | None = None
    plan_type: PlanType | None = None
    recurring_interval: DurationUnit | None = None
    recurring_interval_count: int | None = None
    active: bool = True
    is_default: bool = False

    @model_validator(mode="after")
    def validate_new_price_fields(self) -> PaymentsMembershipPriceItem:
        """New prices (no stripe_price_id) require all pricing fields."""
        if self.stripe_price_id is not None:
            return self

        missing = [
            name
            for name in (
                "unit_amount",
                "plan_type",
                "recurring_interval",
                "recurring_interval_count",
            )
            if getattr(self, name) is None
        ]
        if missing:
            raise ValueError(f"New prices require: {', '.join(missing)}")
        return self


class PaymentsMembershipCreateRequest(BaseModel):
    """Create a Stripe Product with one or more Prices."""

    plan_name: str
    prices: list[PaymentsMembershipPriceItem]
    class_count: int | None = None
    metadata: dict[str, str] = {}

    @model_validator(mode="after")
    def validate_prices(self) -> PaymentsMembershipCreateRequest:
        """Exactly one default price; no existing price IDs on create."""
        defaults = [p for p in self.prices if p.is_default]
        if len(defaults) != 1:
            raise ValueError("Exactly one price must have is_default=True")

        existing = [p for p in self.prices if p.stripe_price_id]
        if existing:
            raise ValueError("Cannot reference existing stripe_price_id on create")
        return self


class PaymentsMembershipUpdateRequest(PaymentsMembershipCreateRequest):
    """Update a Stripe Product and reconcile its Prices."""

    stripe_product_id: str

    @model_validator(mode="after")
    def validate_prices(self) -> PaymentsMembershipUpdateRequest:
        """Exactly one default price; existing price IDs allowed."""
        defaults = [p for p in self.prices if p.is_default]
        if len(defaults) != 1:
            raise ValueError("Exactly one price must have is_default=True")
        return self


class PaymentsMembershipDeactivateRequest(BaseModel):
    """Deactivate (archive) a Stripe Product."""

    stripe_product_id: str


class PaymentsMembershipResponse(BaseModel):
    """Response after creating/updating/deactivating a Stripe membership."""

    stripe_product_id: str
    active: bool
    name: str
    prices: list[PaymentsPriceResponse]
    metadata: dict[str, str] = {}
