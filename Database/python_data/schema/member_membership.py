from datetime import date
from typing import Literal, Optional
from uuid import UUID

from pydantic import computed_field

from . import SeedModel


class MemberMembershipCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    start_date: date
    end_date: Optional[date] = None
    cancel_date: Optional[date] = None
    freeze_start_date: Optional[date] = None
    freeze_end_date: Optional[date] = None
    last_paid_date: Optional[date] = None
    next_due_date: Optional[date] = None
    total_price: float
    discount_ids: Optional[list[UUID]] = None

    def to_insert_dict(self) -> dict:
        data = super().to_insert_dict()
        data.pop("status", None)
        return data

    @computed_field
    @property
    def status(self) -> Literal["active", "frozen", "cancelled", "ended"]:
        today = date.today()
        if self.cancel_date is not None and self.cancel_date <= today:
            return "cancelled"
        if self.end_date is not None and self.end_date <= today:
            return "ended"
        if (
            self.freeze_start_date is not None
            and self.freeze_end_date is not None
            and self.freeze_start_date <= today <= self.freeze_end_date
        ):
            return "frozen"
        return "active"
