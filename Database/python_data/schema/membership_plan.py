from typing import Optional
from uuid import UUID

from . import SeedModel


class MembershipPlanCreate(SeedModel):
    plan_id: UUID
    gym_id: UUID
    plan_name: str
    plan_type: Optional[str] = None
    base_cost: float
    additional_member_costs: Optional[list] = None
    billing_cycle: str
    is_active: bool = True
