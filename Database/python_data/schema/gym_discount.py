from enum import StrEnum
from uuid import UUID

from . import SeedModel


class DiscountType(StrEnum):
    """Discount type: preset | custom."""

    preset = "preset"
    custom = "custom"


class DiscountDurationUnit(StrEnum):
    """Duration span unit for a discount's lifetime.

    Mirrors the Postgres `discount_duration_unit` enum. Distinct from
    membership_plans' duration_unit (week/month/year). `cycle` is plan-relative
    (one cycle = the membership's plan billing period, resolved to an absolute
    end_date at apply-time); a 1-cycle span is the single-invoice discount that
    replaced the old `once` mode.
    """

    day = "day"
    week = "week"
    month = "month"
    cycle = "cycle"


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
