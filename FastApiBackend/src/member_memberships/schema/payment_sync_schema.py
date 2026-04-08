"""Intermediate data models for the membership-to-Stripe sync flow."""

from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import DurationUnit

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)


class ParentProfile(BaseModel):
    """Paying parent's profile fields needed for sync."""

    crm_user_id: UUID
    gym_id: UUID
    stripe_customer_id: str
    stripe_sub_id_week: str | None = None
    stripe_sub_id_month: str | None = None
    stripe_sub_id_year: str | None = None


class ActiveMembershipRow(BaseModel):
    """One active recurring membership joined with plan + price info."""

    crm_user_id: UUID
    plan_id: UUID
    price_id: UUID
    stripe_price_id: str
    stripe_item_id: str | None
    duration_unit: DurationUnit
    discount_ids: list[UUID]
    price: int


class LinkedDiscountInfo(BaseModel):
    """A linked discount resolved from gym_discounts.

    Linked discounts are always dollar_off (enforced by DB constraint).
    """

    discount_id: UUID
    stripe_coupon_id: str
    dollar_off: int


class IntervalDesiredItem(BaseModel):
    """A desired subscription item paired with its billing interval."""

    item: PaymentsSubscriptionDesiredItem
    duration_unit: DurationUnit
    price: int


class IntervalBucket(BaseModel):
    """All items and discounts for one billing interval."""

    interval: DurationUnit
    items: list[PaymentsSubscriptionDesiredItem]
    subscription_discounts: list[SubscriptionItemDiscount] = []
    existing_sub_id: str | None = None
    total_price: int = 0
