from datetime import date
from enum import StrEnum
from uuid import UUID

from pydantic import model_validator

from . import SeedModel


class DiscountType(StrEnum):
    """Discount type.

    Presets (gym_discounts) are regular-only: preset | custom. `linked` is a
    snapshot-only marker that lives on member_membership_applied_discounts (a
    family discount has no preset entity), so it stays in this shared enum but
    is rejected by GymDiscountCreate below.
    """

    preset = "preset"
    custom = "custom"
    linked = "linked"


class DiscountMode(StrEnum):
    """Discount lifetime mode. Mirrors the Postgres `discount_mode` enum.

    Declared here because gym_discounts.sql (the preset) is the earliest-loaded
    consumer; member_membership_applied_discount imports it from here.
    """

    once = "once"
    ongoing = "ongoing"


class DiscountDurationUnit(StrEnum):
    """Duration span unit for an ongoing discount's lifetime.

    Mirrors the Postgres `discount_duration_unit` enum. Distinct from
    membership_plans' duration_unit (week/month/year) — discounts use
    day/week/month.
    """

    day = "day"
    week = "week"
    month = "month"


class GymDiscountCreate(SeedModel):
    """Regular-only, coupon-free discount preset.

    Lifetime spec: discount_mode (once | ongoing) plus, for ongoing, an end set
    by EITHER a duration span (duration_amount + duration_unit) OR an explicit
    end_date — never both; neither = forever. Coupons are computed at sync, not
    stored on the preset, so there is no stripe_coupon_id here.
    """

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    percentage_off: float | None = None
    dollar_off: int | None = None
    discount_mode: DiscountMode
    duration_amount: int | None = None
    duration_unit: DiscountDurationUnit | None = None
    end_date: date | None = None
    is_deleted: bool = False

    @model_validator(mode="after")
    def validate_discount_fields(self) -> "GymDiscountCreate":
        if self.discount_type == DiscountType.linked:
            raise ValueError("gym_discounts presets are regular-only (preset | custom)")

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
