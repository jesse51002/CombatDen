"""Models for membership plan types used in class allocation."""

from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import PlanType


class PlanInfo(BaseModel):
    """Plan metadata needed for allocation priority.

    Attributes:
        plan_id: The membership plan identifier.
        plan_type: Trial, one_time, or recurring.
        class_count: Max classes allowed. None means unlimited.
    """

    plan_id: UUID
    plan_type: PlanType
    class_count: int | None
