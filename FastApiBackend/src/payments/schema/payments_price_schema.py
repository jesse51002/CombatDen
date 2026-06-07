from pydantic import BaseModel
from schema.membership_plan import DurationUnit, PlanType

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.metadata.stripe_price_metadata import (
    StripePriceMetadata,
)


class PaymentsPriceCreateRequest(BaseModel):
    """Create a Stripe Price on a product."""

    stripe_product_id: str
    unit_amount: int
    currency: str = "usd"
    plan_type: PlanType
    recurring_interval: DurationUnit
    recurring_interval_count: int
    metadata: StripePriceMetadata | None = None


class PaymentsPriceResponse(BaseModel):
    """Stripe Price details."""

    stripe_price_id: str
    stripe_product_id: str
    unit_amount: int
    currency: str
    active: bool
    recurring_interval: str | None = None
    recurring_interval_count: int | None = None
