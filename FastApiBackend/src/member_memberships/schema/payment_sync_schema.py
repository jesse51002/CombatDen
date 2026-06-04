"""Intermediate data models for the membership-to-Stripe sync flow."""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)
from src.shared.gym_timezone import gym_today


class ParentProfile(BaseModel):
    """Paying parent's profile fields needed for sync."""

    member_id: UUID
    gym_id: UUID
    stripe_customer_id: str
    stripe_sub_id_month: str | None = None
    freeze_start_date: date | None = None
    freeze_end_date: date | None = None
    timezone: str = "America/Chicago"

    @property
    def is_frozen(self) -> bool:
        """Whether the parent account is currently in a freeze window."""
        if self.freeze_start_date is None or self.freeze_end_date is None:
            return False
        today = gym_today(self.timezone)
        return self.freeze_start_date <= today <= self.freeze_end_date


class ActiveMembershipRow(BaseModel):
    """One active recurring membership joined with plan + price info."""

    member_id: UUID
    plan_id: UUID
    price_id: UUID
    stripe_price_id: str
    stripe_item_id: str
    duration_unit: DurationUnit
    discount_ids: list[UUID]
    price: int


class LinkedDiscountInfo(BaseModel):
    """A discount resolved from gym_discounts with its Stripe coupon.

    Reused for both linked (dollar_off, enforced by DB constraint)
    and regular plan-level discounts (which may be percentage_off),
    so ``dollar_off`` is optional — only populated for discounts
    that actually store a dollar amount.
    """

    discount_id: UUID
    stripe_coupon_id: str
    dollar_off: int | None = None


class MembershipInfo(BaseModel):
    """Identifies a membership for include/exclude operations."""

    member_id: UUID
    plan_id: UUID
    has_linked_discount: bool = False


class SyncItem(BaseModel):
    """Enriched item for update_payments_recurring.

    Carries both Stripe fields (for subscription sync) and
    CRM fields (for linked discount calculation).
    """

    stripe_price_id: str
    stripe_item_id: str | None = None
    member_id: UUID
    plan_id: UUID
    has_linked_discount: bool = False
    quantity: int = 1
    prorate: bool = True
    discount_ids: list[UUID] = Field(default_factory=list)

    def to_membership_info(self) -> MembershipInfo:
        """Extract MembershipInfo for linked discount calc."""
        return MembershipInfo(
            member_id=self.member_id,
            plan_id=self.plan_id,
            has_linked_discount=self.has_linked_discount,
        )


class IntervalDesiredItem(BaseModel):
    """A desired subscription item paired with its billing interval.

    duration_unit is a Literal — recurring plans are monthly-only
    (enforced by DB constraint recurring_must_be_monthly). A non-month
    value here indicates a data integrity issue.
    """

    item: PaymentsSubscriptionDesiredItem
    duration_unit: Literal[DurationUnit.month]
    price: int


class IntervalBucket(BaseModel):
    """All items and discounts for one billing interval."""

    interval: DurationUnit
    items: list[PaymentsSubscriptionDesiredItem]
    subscription_discounts: list[SubscriptionItemDiscount] = []
    existing_sub_id: str | None = None
    total_price: int = 0
