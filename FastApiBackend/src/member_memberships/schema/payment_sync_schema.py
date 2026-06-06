"""Intermediate data models for the membership-to-Stripe sync flow."""

from datetime import date
from typing import Self
from uuid import UUID

from pydantic import BaseModel, Field, model_validator
from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)
from src.shared.billing_parent import ParentProfile


class AppliedDiscount(BaseModel):
    """One applied discount, read for the sync and carried on its membership.

    Rides its ``ActiveMembershipRow`` (``ActiveMembershipRow.discounts``): the
    discount belongs to the membership, not a parallel list. The sync groups
    memberships into consolidated lines by ``price_id``, computes each line's
    effective coupon from the line's memberships' discounts, and writes the
    resolved ``stripe_coupon_id`` back. ``end_date`` and ``stripe_coupon_id`` are
    sync writebacks and may be null until resolved: a ``once`` row's ``end_date``
    is null until the sync stamps it on consumption; an ongoing row's
    ``end_date`` is resolved at apply-time (or null = forever).
    """

    applied_discount_id: UUID
    item_id: UUID
    member_id: UUID
    plan_id: UUID
    stripe_item_id: str | None = None
    discount_mode: DiscountMode
    percentage_off: float | None = None
    dollar_off: int | None = None
    end_date: date | None = None
    stripe_coupon_id: str | None = None


class ActiveMembershipRow(BaseModel):
    """One active recurring membership joined with plan + price info.

    Carries its active discounts (``discounts``): the discount belongs to the
    membership, so it rides the row rather than a parallel list. The sync groups
    these rows by ``price_id`` into consolidated lines and reads each line's
    discounts straight off its memberships.
    """

    item_id: UUID
    member_id: UUID
    plan_id: UUID
    price_id: UUID
    stripe_price_id: str
    stripe_item_id: str | None = None
    duration_unit: DurationUnit
    price: int
    discounts: list[AppliedDiscount] = []


class OnceDiscount(BaseModel):
    """An attached-but-unconsumed ``once`` discount, for the consumption check.

    The minimal projection the once-discount sync needs: the row to stamp and
    the coupon to look for on the live subscription. The DB query already
    guarantees ``once`` + no end_date + a non-null coupon, so the only thing
    left is whether the coupon is still present (pending) or gone (consumed).
    """

    applied_discount_id: UUID
    stripe_coupon_id: str


class SyncItem(BaseModel):
    """Enriched item for update_payments_recurring.

    Carries the Stripe fields needed to reconcile the subscription. Discounts
    are no longer threaded through here — they ride the membership row and are
    computed per consolidated line at sync.
    """

    stripe_price_id: str
    stripe_item_id: str | None = None
    member_id: UUID
    plan_id: UUID
    quantity: int = 1
    prorate: bool = True


class IntervalBucket(BaseModel):
    """All items for one billing interval (discounts ride the items)."""

    interval: DurationUnit
    items: list[PaymentsSubscriptionDesiredItem]
    existing_sub_id: str | None = None


class LineDiscountValue(BaseModel):
    """One consolidated line's effective discount value for a single mode.

    Computed per-line at sync from the line's memberships' discounts: percents
    compound **sequentially within a membership** then the per-membership
    effective fractions are averaged across the line (÷ quantity); fixed dollars
    are summed. Exactly one of ``percentage_off`` / ``dollar_off`` is set.
    ``once`` and ``ongoing`` never mix into the same value.

    ``contributing_ids`` are the applied-discount rows of this exact mode that
    fed the value — the sync writes the value's resolved coupon back onto only
    these, so a line mixing a ``once`` and an ``ongoing`` value records each
    coupon on its own contributors and keeps the ``once`` presence handle exact.
    """

    discount_mode: DiscountMode
    percentage_off: float | None = Field(default=None, gt=0, le=100)
    dollar_off: int | None = Field(default=None, gt=0)
    contributing_ids: list[UUID] = []

    @model_validator(mode="after")
    def _exactly_one_value(self) -> Self:
        """A coupon is percent XOR dollar — exactly one must be set.

        Belt-and-braces over the aggregation: a value can never be both, both
        null, negative, or a percent above 100 — an impossible computed discount
        raises loudly here instead of mis-billing.
        """
        if (self.percentage_off is None) == (self.dollar_off is None):
            raise ValueError(
                "LineDiscountValue must set exactly one of "
                "percentage_off / dollar_off"
            )
        return self


class ResolvedDiscounts(BaseModel):
    """The discount service's resolved output for one sync.

    ``coupons_by_price`` maps each consolidated line's ``price_id`` to the
    coupons to attach to its bucket item (dollar coupon first, then percent, so
    Stripe sequences dollar→percent). ``links`` maps each contributing
    ``applied_discount_id`` to the coupon it resolved to — the **real** path
    writes these back (a ``once`` value records its coupon, the consumption
    handle, on its rows; an ``ongoing`` value on its rows).
    """

    coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]] = {}
    links: dict[UUID, str] = {}


class SyncParams(BaseModel):
    """Resolved inputs shared by the real and preview sync paths.

    The discount coupons are resolved onto ``bucket`` at build time (by
    ``PaymentSyncDiscounts``, for both real and preview, so preview reflects
    discounts). ``coupon_links`` is the resulting ``applied_discount_id →
    coupon_id`` map the **real** path writes back onto the applied-discount rows
    (preview writes nothing).
    """

    bucket: IntervalBucket
    parent: ParentProfile
    stripe_account_id: str
    coupon_links: dict[UUID, str] = {}
    memberships: list[ActiveMembershipRow] = []
