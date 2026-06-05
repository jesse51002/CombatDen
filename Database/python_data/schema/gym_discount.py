from enum import StrEnum
from uuid import UUID

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
    """Discount IDENTITY (preset | custom | linked).

    Coupon-free and value-free: a discount's percent/dollar + lifetime spec live
    in versioned, immutable rows on gym_discount_values (see GymDiscountValueCreate).
    Editing a value mints a new version there; this identity row (name, type)
    stays stable. A `linked` discount is a real entry that a membership plan's
    family tiers reference by id.
    """

    discount_id: UUID
    gym_id: UUID
    discount_name: str
    discount_type: DiscountType
    is_deleted: bool = False
