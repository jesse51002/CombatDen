"""Pydantic models for the rewards domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field
from schema.member_reward_redemption import RewardRedemptionStatus

import src.shared.db_schema_path  # noqa: F401  — ensures ``from schema.*`` path is set up


class RewardCreateRequest(BaseModel):
    """Body for POST /api/v1/rewards/."""

    gym_id: UUID
    title: str = Field(min_length=1)
    point_cost: int = Field(gt=0)
    amount_off: str | None = None
    image_url: str | None = None
    price_label: str | None = None


class RewardUpdateData(BaseModel):
    """Mutable fields on a reward row."""

    title: str | None = None
    point_cost: int | None = Field(default=None, gt=0)
    amount_off: str | None = None
    image_url: str | None = None
    price_label: str | None = None
    is_active: bool | None = None


class RewardUpdateRequest(BaseModel):
    """Body for PUT /api/v1/rewards/{reward_id}."""

    data: RewardUpdateData


class RewardResponse(BaseModel):
    """A single gym_rewards row."""

    reward_id: UUID
    gym_id: UUID
    title: str
    point_cost: int
    amount_off: str | None
    image_url: str | None
    price_label: str | None = None
    is_active: bool
    created_at: datetime


class RewardListResponse(BaseModel):
    """List of rewards."""

    items: list[RewardResponse]


class RedemptionRequest(BaseModel):
    """Body for POST /api/v1/rewards/{reward_id}/redeem."""

    member_id: UUID


class RedeemForMemberRequest(BaseModel):
    """Body for POST /api/v1/rewards/{reward_id}/redeem-for-member."""

    member_id: UUID
    override: bool = False


class RedemptionResponse(BaseModel):
    """A single member_reward_redemptions row (full redemption result)."""

    redemption_id: UUID
    member_id: UUID
    reward_id: UUID
    gym_id: UUID
    point_cost: int
    redeemed_at: datetime
    status: RewardRedemptionStatus
    decided_at: datetime | None
    points_balance_after: int


class RedemptionTransitionResponse(BaseModel):
    """Response for approve / reject admin transitions."""

    redemption_id: UUID
    status: RewardRedemptionStatus
    decided_at: datetime
    points_balance_after: int | None = None


class RedemptionHistoryItem(BaseModel):
    """A single redemption joined with reward fields."""

    redemption_id: UUID
    reward_id: UUID
    title: str
    image_url: str | None
    amount_off: str | None
    point_cost: int
    redeemed_at: datetime
    status: RewardRedemptionStatus


class RedemptionHistoryResponse(BaseModel):
    """A member's reward redemption history."""

    items: list[RedemptionHistoryItem]


class PendingRedemptionItem(BaseModel):
    """One row from the gym-wide pending redemption queue."""

    redemption_id: UUID
    member_id: UUID
    member_name: str
    reward_title: str
    reward_image_url: str | None
    point_cost: int
    redeemed_at: datetime


class PendingRedemptionListResponse(BaseModel):
    """Gym-wide pending redemption queue."""

    items: list[PendingRedemptionItem]
