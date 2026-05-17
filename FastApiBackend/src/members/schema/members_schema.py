"""Pydantic models for the members domain."""

from datetime import date, datetime
from enum import StrEnum
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from src.ranks.schema.ranks_schema import RankSummary


class MemberStatus(StrEnum):
    """Computed status from the ``members_with_status`` view."""

    trial = "trial"
    active = "active"
    inactive = "inactive"


class MemberCreateRequest(BaseModel):
    """Body for POST /api/v1/members/."""

    gym_id: UUID
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    email: EmailStr | None = None
    user_id: UUID | None = None
    trial_start_date: date | None = None
    trial_end_date: date | None = None
    fully_active_start_date: date | None = None
    inactive_start_date: date | None = None
    current_rank_id: UUID | None = None


class MemberUpdateData(BaseModel):
    """Mutable fields on a member row."""

    first_name: str | None = None
    last_name: str | None = None
    email: EmailStr | None = None
    trial_start_date: date | None = None
    trial_end_date: date | None = None
    fully_active_start_date: date | None = None
    inactive_start_date: date | None = None
    current_rank_id: UUID | None = None


class MemberUpdateRequest(BaseModel):
    """Body for PUT /api/v1/members/{member_id}."""

    data: MemberUpdateData


class MemberListItem(BaseModel):
    """A single row in the members list."""

    member_id: UUID
    first_name: str
    last_name: str
    email: str | None
    status: MemberStatus
    last_class_days_ago: int | None
    points_balance: int
    current_rank: RankSummary | None


class MemberListResponse(BaseModel):
    """Paginated members list."""

    items: list[MemberListItem]
    total: int


class MembersListRequest(BaseModel):
    """Body for POST /api/v1/members/list."""

    gym_id: UUID
    requested_view: Literal["all", "trial", "active", "inactive"] = "all"
    search: str | None = None
    limit: int = Field(default=50, ge=1, le=200)
    offset: int = Field(default=0, ge=0)


class MembersTotalCounts(BaseModel):
    """Unfiltered total counts per status."""

    all: int
    trial: int
    active: int
    inactive: int


class RedeemedReward(BaseModel):
    """A single redeemed reward in member detail."""

    redemption_id: UUID
    reward_id: UUID
    title: str
    image_url: str | None
    amount_off: str | None
    point_cost: int
    redeemed_at: datetime


class MemberResponse(BaseModel):
    """Bare member row (used by create / update endpoints)."""

    member_id: UUID
    gym_id: UUID
    user_id: UUID | None
    first_name: str
    last_name: str
    email: str | None
    points_balance: int
    last_class: datetime | None
    trial_start_date: date | None
    trial_end_date: date | None
    fully_active_start_date: date | None
    inactive_start_date: date | None
    current_rank_id: UUID | None
    created_at: datetime


class MemberDetailResponse(BaseModel):
    """Full member detail for the AppManagement member screen."""

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    email: str | None
    status: MemberStatus
    points_balance: int
    last_class: datetime | None
    last_class_days_ago: int | None
    class_streak_weeks: int
    trial_start_date: date | None
    trial_end_date: date | None
    fully_active_start_date: date | None
    inactive_start_date: date | None
    current_rank: RankSummary | None
    created_at: datetime
    redeemed_rewards: list[RedeemedReward]
