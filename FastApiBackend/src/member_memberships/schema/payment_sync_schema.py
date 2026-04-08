"""Intermediate data models for the membership-to-Stripe sync flow."""

from uuid import UUID

from pydantic import BaseModel
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
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


class MembershipInfo(BaseModel):
    """Identifies a membership for include/exclude operations."""

    crm_user_id: UUID
    plan_id: UUID
    has_linked_discount: bool = False


class SyncItem(BaseModel):
    """Enriched item for update_payments_recurring.

    Carries both Stripe fields (for subscription sync) and
    CRM fields (for linked discount calculation).
    """

    stripe_price_id: str
    stripe_item_id: str | None = None
    crm_user_id: UUID
    plan_id: UUID
    has_linked_discount: bool = False
    quantity: int = 1
    prorate: bool = True

    def to_desired_item(self) -> PaymentsSubscriptionDesiredItem:
        """Strip to PaymentsSubscriptionDesiredItem for Stripe."""
        return PaymentsSubscriptionDesiredItem(
            stripe_price_id=self.stripe_price_id,
            stripe_item_id=self.stripe_item_id,
            prorate=self.prorate,
            quantity=self.quantity,
        )

    def to_membership_info(self) -> MembershipInfo:
        """Extract MembershipInfo for linked discount calc."""
        return MembershipInfo(
            crm_user_id=self.crm_user_id,
            plan_id=self.plan_id,
            has_linked_discount=self.has_linked_discount,
        )


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
