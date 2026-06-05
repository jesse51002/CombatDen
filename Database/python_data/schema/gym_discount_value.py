from datetime import date
from uuid import UUID

from pydantic import model_validator

from . import SeedModel
from .gym_discount import DiscountDurationUnit, DiscountMode

__all__ = [
    "DiscountDurationUnit",
    "DiscountMode",
    "GymDiscountValueCreate",
]


class GymDiscountValueCreate(SeedModel):
    """A versioned, immutable discount VALUE row (gym_discount_values).

    A gym_discounts identity owns one or more value versions. Editing a
    discount's value inserts a NEW active version (is_active=True) and
    deactivates the old one — a permanent paper trail. Applied snapshots
    reference value_id, freezing a member's discount to the exact version.

    Lifetime spec: discount_mode (once | ongoing) plus, for ongoing, an end set
    by EITHER a duration span (duration_amount + duration_unit) OR an explicit
    end_date — never both; neither = forever. Coupons are computed at sync (not
    stored here), so there is no stripe_coupon_id.
    """

    value_id: UUID
    discount_id: UUID
    gym_id: UUID
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None
    is_active: bool = True

    @model_validator(mode="after")
    def validate_value_fields(self) -> "GymDiscountValueCreate":
        has_pct = self.percentage_off is not None
        has_dollar = self.dollar_off is not None
        if has_pct == has_dollar:
            raise ValueError("Exactly one of percentage_off or dollar_off must be set")

        has_amount = self.duration_amount is not None
        has_unit = self.duration_unit is not None
        if has_amount != has_unit:
            raise ValueError("duration_amount and duration_unit must be set together")
        if has_amount and self.end_date is not None:
            raise ValueError(
                "lifetime is a duration span OR an explicit end_date, never both"
            )
        return self
