from datetime import date
from enum import StrEnum
from typing import Optional
from uuid import UUID

from pydantic import computed_field

from . import SeedModel


class MembershipDbStatus(StrEnum):
    """Raw membership status as derived by the DB view."""

    active = "active"
    frozen = "frozen"
    cancelled = "cancelled"
    ended = "ended"


class MemberMembershipCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    start_date: date
    end_date: Optional[date] = None
    cancel_date: Optional[date] = None
    freeze_start_date: Optional[date] = None
    freeze_end_date: Optional[date] = None
    last_paid_date: Optional[date] = None
    next_due_date: Optional[date] = None
    prorate: bool = True
    total_price: int
    price_formula: Optional[str] = None
    discount_ids: Optional[list[UUID]] = None
    stripe_item_id: Optional[str] = None

    def to_insert_dict(self) -> dict:
        data = super().to_insert_dict()
        data.pop("status", None)
        return data

    @computed_field
    @property
    def status(self) -> MembershipDbStatus:
        today = date.today()
        if self.cancel_date is not None and self.cancel_date <= today:
            return MembershipDbStatus.cancelled
        if self.end_date is not None and self.end_date <= today:
            return MembershipDbStatus.ended
        if (
            self.freeze_start_date is not None
            and self.freeze_end_date is not None
            and self.freeze_start_date <= today <= self.freeze_end_date
        ):
            return MembershipDbStatus.frozen
        return MembershipDbStatus.active
