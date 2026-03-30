from datetime import date
from typing import Literal, Optional
from uuid import UUID

from . import SeedModel


class MemberMembershipCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    start_date: date
    status: Literal["active", "frozen", "cancelled"] = "active"
    last_paid_date: Optional[date] = None
    next_due_date: Optional[date] = None
    discount_ids: Optional[list[UUID]] = None
    custom_discounts: Optional[list[dict]] = None
