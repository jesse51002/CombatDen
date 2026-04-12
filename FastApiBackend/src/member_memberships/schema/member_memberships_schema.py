"""Request schemas for member membership lifecycle operations."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel, Field


class MemberMembershipsFreezeRequest(BaseModel):
    """Freeze a member's account (account-level)."""

    crm_user_id: UUID
    gym_id: UUID
    freeze_months: int = Field(..., gt=0)


class MemberMembershipsUnfreezeRequest(BaseModel):
    """Unfreeze a member's account (account-level)."""

    crm_user_id: UUID
    gym_id: UUID


class MemberMembershipsStartRequest(BaseModel):
    """Start a new membership for a member."""

    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    price_id: UUID
    start_date: date
    discount_ids: list[UUID] | None = None
    include_linked_discount: bool = False
    prorate: bool = True


class MemberMembershipsUpdatePriceRequest(BaseModel):
    """Update the price of an existing membership."""

    item_id: UUID
    crm_user_id: UUID
    new_price_id: UUID
    prorate: bool = False
