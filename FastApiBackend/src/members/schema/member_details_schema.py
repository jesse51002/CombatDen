"""Pydantic schemas for the members domain."""

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel
from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType
from schema.user_gym_charge import ChargeKind, ChargeStatus
from schema.user_gym_invoice_line_item import LineItemType


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


class PayingForMember(LinkedAccount):
    """A member on a plan with their class usage for the current cycle.

    Extends LinkedAccount with cycle-based class usage fields.
    """

    status: MembershipDbStatus
    class_count: int | None = None
    classes_used: int = 0
    classes_remaining: int | None = None


class DiscountInfo(BaseModel):
    """An active discount applied to a membership."""

    discount_id: UUID
    discount_name: str
    discount_type: str
    percentage_off: float | None = None
    dollar_off: float | None = None
    end_date: date | None = None


class MembershipInfo(BaseModel):
    """A grouped plan in the membership carousel.

    Represents one unique plan across the family group,
    with a list of which members are covered by this plan.
    """

    plan_id: UUID
    plan_name: str
    plan_type: PlanType | None = None
    status: MembershipDbStatus
    base_cost: float
    duration_amount: int
    duration_unit: str
    total_cost: float
    cost_formula: str | None = None
    additional_member_discount: float | None = None
    last_paid_date: date | None = None
    next_due_date: date | None = None
    start_date: date
    end_date: date | None = None
    freeze_start_date: date | None = None
    freeze_end_date: date | None = None
    paying_for: list[PayingForMember] = []
    discounts: list[DiscountInfo] = []


class Retention(BaseModel):
    """Member retention and engagement statistics."""

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


class LineItemRecord(BaseModel):
    """A single line item on an invoice."""

    line_item_id: str
    item_type: LineItemType
    name: str
    amount: int
    stripe_product_id: str | None = None
    item_id: UUID | None = None


class PaymentRecord(BaseModel):
    """A single charge (payment or refund) against an invoice."""

    charge_id: UUID
    invoice_id: UUID
    kind: ChargeKind
    status: ChargeStatus
    amount: int  # signed: payment >= 0, refund <= 0
    currency: str
    payment_method_type: str | None = None
    charge_time: datetime
    refunds_charge_id: UUID | None = None
    line_items: list[LineItemRecord] = []
    applied_discounts: list[DiscountInfo] = []


class MemberDetailResponse(BaseModel):
    """Full member detail response for the Specific Member screen."""

    crm_user_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None
    account_status: str | None = None
    membership_overview: str
    linked_to_account: UUID | None = None
    total_membership_count: int
    personal_info: PersonalInfo
    linked_accounts: list[LinkedAccount] = []
    memberships: list[MembershipInfo]
    retention: Retention
    recently_redeemed_rewards: list[RewardCard] = []
    payment_history: list[PaymentRecord] = []
