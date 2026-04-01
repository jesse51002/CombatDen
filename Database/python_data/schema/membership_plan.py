from typing import Literal, Optional
from uuid import UUID

from . import SeedModel


class MembershipPlanCreate(SeedModel):
    plan_id: UUID
    gym_id: UUID
    plan_name: str
    plan_type: Literal["trial", "recurring", "one_time"]
    base_cost: float
    additional_member_costs: Optional[list] = None
    class_count: Optional[int] = None
    duration_amount: int
    duration_unit: Literal["week", "month", "year"]
