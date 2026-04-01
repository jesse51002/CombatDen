"""Pydantic schemas for the members domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class PersonalInfo(BaseModel):
    """Member personal information and emergency contact."""

    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    waiver_id: str | None = None


class LinkedAccount(BaseModel):
    """A linked family/group member account."""

    crm_user_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None


class DiscountInfo(BaseModel):
    """An active discount applied to a membership."""

    discount_id: UUID
    discount_name: str
    percentage_off: float | None = None
    dollar_off: float | None = None
    start_date: datetime | None = None
    end_date: datetime | None = None


class MembershipInfo(BaseModel):
    """Membership details including cost, dates, linked accounts, and discounts."""

    plan_name: str
    plan_type: str | None = None
    status: str
    base_cost: float
    billing_cycle: str
    total_cost: float
    cost_formula: str
    last_paid_date: datetime | None = None
    next_due_date: datetime | None = None
    start_date: datetime
    linked_accounts: list[LinkedAccount] = []
    discounts: list[DiscountInfo] = []


class RankRetention(BaseModel):
    """Rank progression and retention statistics."""

    current_rank: int | None = None
    rank_name: str | None = None
    rank_image_url: str | None = None
    classes_in_rank: int
    estimated_classes_for_rank: int
    recommend_promo_in: int | None = None
    last_class: datetime | None = None
    class_streak_weeks: int
    points_balance: int
    videos_watched: int


class RewardCard(BaseModel):
    """A recently redeemed reward."""

    reward_id: UUID
    title: str
    amount_off: str | None = None
    image_url: str | None = None
    point_cost: int


class PaymentRecord(BaseModel):
    """A single payment transaction."""

    transaction_id: UUID
    item_type: str | None = None
    amount_paid: float
    time: datetime


class MemberDetailResponse(BaseModel):
    """Full member detail response for the Specific Member screen."""

    crm_user_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None
    account_status: str | None = None
    personal_info: PersonalInfo
    membership: MembershipInfo
    rank_retention: RankRetention
    recently_redeemed_rewards: list[RewardCard] = []
    payment_history: list[PaymentRecord] = []
