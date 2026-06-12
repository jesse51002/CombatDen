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
from src.shared.payer_profile import PayerProfile


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

    Carries its plan ``price`` (the gross per-unit, in minor units) and its
    active discounts (``discounts``): both belong to the membership, so they
    ride the row rather than parallel lists. The sync groups these rows by
    ``price_id`` into consolidated lines and reads each line's discounts straight
    off its memberships; ``price`` feeds each membership's own post-discount
    amount, derived in the same pass by
    ``PaymentSyncDiscounts._aggregate_line_values``.
    """

    item_id: UUID
    member_id: UUID
    plan_id: UUID
    price_id: UUID
    stripe_price_id: str
    price: int
    stripe_item_id: str | None = None
    # Recurring rows always carry the plan's interval; a one-time row may leave it
    # None (a one-time plan can have no duration). Carried as metadata only — the
    # bucket interval is fixed monthly, so nothing in the build reads it.
    duration_unit: DurationUnit | None = None
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

    ``contributing_ids`` are the applied-discount rows of this exact mode **and
    kind** (percent vs dollar) that fed the value — disjoint, so the sync writes
    the value's resolved coupon back onto only its own contributors. A line
    mixing a percent and a dollar ``once`` records each coupon on its own rows,
    so a dollar-``once``'s presence handle is its own dollar coupon, not the
    percent coupon (keeps the ``once`` consumption check exact).
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
    coupons to attach to its bucket item (percent coupon first, then dollar, so
    Stripe sequences percent→dollar). ``links`` maps each contributing
    ``applied_discount_id`` to the coupon it resolved to — the **real** path
    writes these back (a ``once`` value records its coupon, the consumption
    handle, on its rows; an ``ongoing`` value on its rows).

    ``membership_amounts`` maps each active membership's ``item_id`` to its own
    post-discount price (minor units) — its plan price with its **ongoing**
    discounts always applied and its **once** discounts applied only once the
    membership is on Stripe (its ``stripe_item_id`` is set, so the once applies
    to a future invoice); a not-yet-synced membership excludes its once. It
    covers **every** membership in the sync; the **real** path writes each onto
    its membership row.
    """

    coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]] = {}
    links: dict[UUID, str] = {}
    membership_amounts: dict[UUID, int] = {}


class SyncParams(BaseModel):
    """Resolved inputs shared by the real and preview sync paths.

    The discount coupons are resolved onto ``bucket`` at build time (by
    ``PaymentSyncDiscounts``, for both real and preview, so preview reflects
    discounts). ``coupon_links`` is the resulting ``applied_discount_id →
    coupon_id`` map the **real** path writes back onto the applied-discount rows
    (preview writes nothing). ``membership_post_discount_amounts`` (``item_id →
    cents``) is each membership's own post-discount price the **real** path
    writes onto its ``total_price`` (preview writes nothing).
    """

    bucket: IntervalBucket
    payer: PayerProfile
    stripe_account_id: str
    coupon_links: dict[UUID, str] = {}
    membership_post_discount_amounts: dict[UUID, int] = {}
    memberships: list[ActiveMembershipRow] = []


class OneTimeInvoiceItem(BaseModel):
    """One pending one-time membership as a line on the consolidated invoice.

    Its index in ``OneTimeInvoicePlan.items`` matches the invoice line order
    (``create_invoice_payment`` returns line ids in request order), so the
    writeback maps each returned line id + amount back to this ``item_id``.
    ``coupon_ids`` are the membership's item-level coupons, already ordered
    percent→dollar by the resolver (``DISCOUNT_APPLICATION_ORDER``).
    """

    item_id: UUID
    member_id: UUID
    plan_id: UUID
    stripe_price_id: str
    coupon_ids: list[str] = []


class OneTimeInvoicePlan(BaseModel):
    """The desired one-time consolidated invoice + its discount writebacks.

    The one-time counterpart of ``SyncParams``: an **ordered** list of invoice
    lines (one per pending one-time membership), plus the ``applied_discount_id →
    coupon_id`` links the writeback stamps, and the ``once``-mode applied-discount
    ids to mark consumed (``end_date = today``). Built with **no DB writes**.
    """

    items: list[OneTimeInvoiceItem] = []
    payer: PayerProfile
    stripe_account_id: str
    coupon_links: dict[UUID, str] = {}
    once_consumed_ids: list[UUID] = []
