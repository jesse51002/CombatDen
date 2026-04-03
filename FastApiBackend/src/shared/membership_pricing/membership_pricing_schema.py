"""Pydantic models for membership pricing input and output."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel


class MemberMembershipInput(BaseModel):
    """One membership row for pricing calculation."""

    crm_user_id: UUID
    plan_id: UUID
    status: str
    is_additional_member: bool
    discount_ids: list[UUID] = []


class PlanInput(BaseModel):
    """Plan details needed for pricing."""

    plan_id: UUID
    plan_name: str
    plan_type: str
    base_cost: float
    additional_member_discount: float | None = None


class DiscountInput(BaseModel):
    """A gym discount available for pricing."""

    discount_id: UUID
    discount_name: str
    percentage_off: float | None = None
    dollar_off: float | None = None
    end_date: date | None = None


class AccountPricingInput(BaseModel):
    """All data the pricing service needs for a family account."""

    memberships: list[MemberMembershipInput]
    plans: dict[UUID, PlanInput]
    discounts: dict[UUID, DiscountInput]


class MembershipPriceResult(BaseModel):
    """Pricing result for one membership row."""

    crm_user_id: UUID
    plan_id: UUID
    calculated_price: float
    cost_formula: str | None = None


class AccountPricingResult(BaseModel):
    """Pricing result for the whole family account."""

    active_total: float
    frozen_total: float
    has_trial: bool = False
    has_cancelled: bool = False
    paying_count: int = 0
    membership_prices: list[MembershipPriceResult]
