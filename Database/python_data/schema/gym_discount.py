from enum import StrEnum
from uuid import UUID

from . import SeedModel


class DiscountType(StrEnum):
    """Discount type: preset | custom."""

    preset = "preset"
    custom = "custom"


class DiscountMode(StrEnum):
    """Discount lifetime mode. Mirrors the Postgres `discount_mode` enum.

    Consumed by gym_discount_values (the versioned value rows). Kept here as the
    stable import location (the backend imports it from schema.gym_discount).
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
    """Discount IDENTITY (preset | custom).

    Coupon-free and value-free: a discount's percent/dollar + lifetime spec live
    in versioned, immutable rows on gym_discount_values (see GymDiscountValueCreate).
    Editing a value mints a new version there; this identity row (name, type)
    stays stable.
    """

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    is_deleted: bool = False
