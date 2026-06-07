"""Pydantic schemas for billing management and member detail."""

from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel
from schema.member_charge import ChargeKind, ChargeStatus
from schema.member_invoice_line_item import LineItemType
from schema.membership_plan import PlanType

from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsAppliedDiscount,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)

# ── Management Request / Response ────────────────────────────────


class MembersBillingUpdateCardRequest(BaseModel):
    """Update a member's payment card. Overwrites DB and Stripe."""

    payment_method_id: str


class MembersBillingProfileResponse(BaseModel):
    """Shared response for card update / payment unlink operations.

    Returned by:
    - PUT  /{member_id}/card
    - DELETE /{member_id}/payment
    """

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None
    account_linked_to_id: UUID | None = None
    stripe_customer_id: str | None = None
    stripe_payment_method_id: str | None = None
    card_brand: str | None = None
    card_last_four: str | None = None
    card_exp_month: int | None = None
    card_exp_year: int | None = None


# ── Member Detail sub-models ──────────────────────────────────────


class BillingPersonalInfo(BaseModel):
    """Member personal information and emergency contact."""

    phone: str | None = None
    email: str | None = None
    address: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    emergency_contact_email: str | None = None


class BillingLinkedAccount(BaseModel):
    """A linked family/group member account."""

    member_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None


class BillingPayingForMember(BillingLinkedAccount):
    """A member on a plan with their class usage for the current cycle."""

    status: CrmMemberStatus
    class_count: int | None = None
    classes_used: int = 0
    classes_remaining: int | None = None


class BillingDiscountInfo(BaseModel):
    """A discount that was applied to a past invoice (payment-history line).

    Sourced from ``member_invoice_applied_discounts`` — the per-invoice audit
    the ``invoice.paid`` webhook captures from Stripe. It is deliberately
    coupon-only (the Stripe coupon id + the dollars it took off this invoice),
    NOT linked back to a CRM discount. Currently-applied membership discounts
    use the snapshot model ``MemberMembershipsAppliedDiscount`` on
    ``BillingMembershipInfo.discounts``.
    """

    stripe_coupon_id: str
    amount_off: int


class BillingMembershipMemberInfo(BaseModel):
    """Per-member membership details within a grouped plan.

    ``base_cost`` and ``total_price`` are this member's own
    ``member_memberships`` numbers (their pinned price and their
    after-discount total), so the CRM can render the membership card
    atomically for one covered member at a time rather than as a
    family-wide aggregate.
    """

    item_id: UUID
    end_date: date | None = None
    cancel_date: date | None = None
    on_outdated_price: bool = False
    base_cost: int
    total_price: int


class BillingMembershipInfo(BaseModel):
    """A grouped plan in the membership carousel."""

    plan_id: UUID
    plan_name: str
    plan_type: PlanType | None = None
    status: CrmMemberStatus
    base_cost: int
    current_active_price: int | None = None
    duration_amount: int
    duration_unit: str
    total_price: int
    last_paid_date: date | None = None
    next_due_date: date | None = None
    start_date: date
    freeze_start_date: date | None = None
    freeze_end_date: date | None = None
    paying_for: list[BillingPayingForMember] = []
    discounts: list[MemberMembershipsAppliedDiscount] = []
    members: dict[UUID, BillingMembershipMemberInfo] = {}


class BillingRetention(BaseModel):
    """Member retention and engagement statistics."""

    last_class: datetime | None = None
    class_streak_weeks: int
    points_balance: int
    videos_watched: int


class BillingRank(BaseModel):
    """Member's current rank (belt) for the rank block.

    Sourced from the member's ``current_rank_id`` row in
    ``gym_ranks``. ``None`` on the response when the member has no
    rank assigned (or the gym has ranks disabled).
    """

    rank_id: UUID
    main_name: str
    sub_name: str
    image_url: str | None = None
    color: str | None = None
    classes_till_rankup: int


class BillingRewardCard(BaseModel):
    """A recently redeemed reward."""

    reward_id: UUID
    title: str
    amount_off: str | None = None
    image_url: str | None = None
    point_cost: int


class BillingLineItemRecord(BaseModel):
    """A single line item on an invoice."""

    line_item_id: str
    item_type: LineItemType
    name: str
    amount: int
    quantity: int = 1
    stripe_product_id: str | None = None
    item_id: UUID | None = None


class BillingInvoiceAttempt(BaseModel):
    """One charge against an invoice — a retry, the success, or a refund.

    The invoice popup lists every attempt so staff see the full payment
    history of a single invoice (e.g. a failed card, then a successful one),
    each with its method and, for a card, the last four digits.
    """

    charge_id: UUID
    kind: ChargeKind
    status: ChargeStatus
    amount: int
    payment_method_type: str | None = None
    card_last_four: str | None = None
    charge_time: datetime


class BillingPaymentRecord(BaseModel):
    """A single charge (payment or refund) against an invoice.

    ``paid_by_*`` identify the account that was charged (the payer) so the
    member-detail history can label each row — the charges are attributed to
    the member by membership, so the payer may be a paying parent.
    """

    charge_id: UUID
    invoice_id: UUID
    kind: ChargeKind
    status: ChargeStatus
    amount: int
    currency: str
    payment_method_type: str | None = None
    charge_time: datetime
    refunds_charge_id: UUID | None = None
    refunded_amount: int = 0
    paid_by_member_id: UUID
    paid_by_first_name: str
    paid_by_last_name: str
    paid_by_photo_url: str | None = None
    line_items: list[BillingLineItemRecord] = []
    applied_discounts: list[BillingDiscountInfo] = []
    attempts: list[BillingInvoiceAttempt] = []


class BillingCardOnFile(BaseModel):
    """Saved card details for the paying account."""

    brand: str
    last_four: str
    exp_month: int
    exp_year: int


class MemberBillingDetailResponse(BaseModel):
    """Full member detail response for the CRM Specific Member screen.

    Extends the standard MemberDetailResponse with billing data:
    memberships, payment history, linked accounts, and card on file.
    """

    member_id: UUID
    gym_id: UUID
    first_name: str
    last_name: str
    photo_url: str | None = None
    account_status: str | None = None
    membership_overview: str
    linked_to_account: UUID | None = None
    total_monthly_recurring_price: int
    total_membership_count: int
    personal_info: BillingPersonalInfo
    linked_accounts: list[BillingLinkedAccount] = []
    memberships: list[BillingMembershipInfo]
    retention: BillingRetention
    rank: BillingRank | None = None
    recently_redeemed_rewards: list[BillingRewardCard] = []
    card_on_file: BillingCardOnFile | None = None
