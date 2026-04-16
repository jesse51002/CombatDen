from enum import StrEnum
from uuid import UUID

from . import SeedModel


class PlanType(StrEnum):
    """Membership plan type, matching the DB CHECK constraint."""

    trial = "trial"
    one_time = "one_time"
    recurring = "recurring"


class DurationUnit(StrEnum):
    """Billing cycle duration unit."""

    week = "week"
    month = "month"
    year = "year"


class MembershipPlanCreate(SeedModel):
    plan_id: UUID
    gym_id: UUID
    plan_name: str
    plan_type: PlanType
    class_count: int | None = None
    duration_amount: int | None = None
    duration_unit: DurationUnit | None = None
    is_public: bool = True
    is_deleted: bool = False
    stripe_product_id: str | None = None
