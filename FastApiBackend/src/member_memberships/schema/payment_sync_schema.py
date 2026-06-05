"""Intermediate data models for the membership-to-Stripe sync flow."""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel
from schema.gym_discount import DiscountMode
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
    """One active recurring membership joined with plan + price info.

    Discounts no longer live on the membership row — they are frozen
    snapshot rows on member_membership_applied_discounts, read separately
    and keyed back to the membership by (item_id / stripe_item_id) at sync.
    """

    item_id: UUID
    member_id: UUID
    plan_id: UUID
    price_id: UUID
    stripe_price_id: str
    stripe_item_id: str
    duration_unit: DurationUnit
    price: int


class AppliedDiscountSnapshot(BaseModel):
    """One frozen applied-discount snapshot read for the sync.

    The sync groups these per consolidated line (keyed by ``stripe_item_id``),
    computes each line's effective coupon, and writes the resolved
    stripe_coupon_id back. ``end_date`` and ``stripe_coupon_id`` are sync
    writebacks and may be null until resolved: a ``once`` snapshot's
    ``end_date`` is null until the sync stamps it on consumption; an ongoing
    snapshot's ``end_date`` is resolved at apply-time (or null = forever).
    """

    applied_discount_id: UUID
    item_id: UUID
    member_id: UUID
    plan_id: UUID
    stripe_item_id: str
    discount_mode: DiscountMode
    percentage_off: float | None = None
    dollar_off: int | None = None
    end_date: date | None = None
    stripe_coupon_id: str | None = None


class SyncItem(BaseModel):
    """Enriched item for update_payments_recurring.

    Carries the Stripe fields needed to reconcile the subscription. Discounts
    are no longer threaded through here — they are read from the applied
    snapshot table and computed per consolidated line at sync.
    """

    stripe_price_id: str
    stripe_item_id: str | None = None
    member_id: UUID
    plan_id: UUID
    quantity: int = 1
    prorate: bool = True


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


class LineDiscountValue(BaseModel):
    """One consolidated line's effective discount value for a single mode.

    Computed per-line at sync from the contributing snapshots: percents are
    summed per unit then divided by the line quantity (the percent×quantity
    fix — a 10% off on 1 of 2 units becomes 5% on the quantity-2 line); fixed
    dollars are summed. Exactly one of ``percentage_off`` / ``dollar_off`` is
    set. ``once`` and ``ongoing`` never mix into the same value.

    ``contributing_ids`` are the snapshot rows of this exact mode that fed the
    value — the sync writes the value's resolved coupon back onto only these,
    so a line mixing a ``once`` and an ``ongoing`` value records each coupon on
    its own contributors and keeps the ``once`` presence handle exact.
    """

    discount_mode: DiscountMode
    percentage_off: float | None = None
    dollar_off: int | None = None
    contributing_ids: list[UUID] = []


class LineDiscountPlan(BaseModel):
    """The discount plan for one consolidated subscription line.

    ``stripe_item_id`` keys the line back to its Stripe subscription item.
    ``values`` is the per-mode effective values to turn into coupons (at most
    one ``once`` and one ``ongoing``), each carrying its own contributing
    snapshot ids. ``consumed_ids`` are ``once`` snapshots the sync found
    already invoiced (coupon absent on the live subscription) — their end_date
    is stamped and they are excluded from ``values``.
    """

    stripe_item_id: str
    values: list[LineDiscountValue] = []
    consumed_ids: list[UUID] = []


class SyncParams(BaseModel):
    """Resolved inputs shared by the real and preview sync paths.

    ``snapshots`` carries the family's applied-discount snapshot rows the
    sync-time coupon computation (``_attach_computed_coupons``) groups per
    consolidated line to compute each line's effective coupon. The real path
    attaches the resolved coupons to ``bucket`` and writes stripe_coupon_id
    back; the preview path leaves them off (a dry run reads no live state).
    """

    bucket: IntervalBucket
    parent: ParentProfile
    stripe_account_id: str
    snapshots: list[AppliedDiscountSnapshot]
