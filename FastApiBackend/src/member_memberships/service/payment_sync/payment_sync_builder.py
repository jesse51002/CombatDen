"""Pure logic for building desired items and grouping by interval.

Discount handling moved out of this module. Discounts are now frozen snapshot
rows on member_membership_applied_discounts; the sync-time coupon computation
(read the subscription's current Stripe discounts, exclude past-end_date /
consumed snapshots, aggregate per consolidated line, find-or-create the coupon,
write stripe_coupon_id back) is owned by the payment_sync phase. This builder
only shapes the desired subscription items and consolidates them by price; the
items carry no discounts here — the coupon step attaches them after.
"""

import logging
from collections import defaultdict
from datetime import date
from uuid import UUID

from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    AppliedDiscountSnapshot,
    IntervalBucket,
    IntervalDesiredItem,
    LineDiscountPlan,
    LineDiscountValue,
    SyncItem,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
)

logger = logging.getLogger(__name__)


def build_desired_items(
    memberships: list[ActiveMembershipRow],
    add_intervals: list[IntervalDesiredItem],
) -> list[IntervalDesiredItem]:
    """Convert current memberships + adds into desired items.

    Cancellations must be applied upstream by filtering
    ``memberships`` on the full ``(member_id, plan_id)`` key
    before calling this function — filtering by
    ``stripe_price_id`` alone is unsafe on shared family plans
    where every member row shares the same price.

    Existing memberships get prorate=False (old items).
    New add_ids keep whatever prorate the caller set. Items carry no
    discounts here — the sync-time coupon step attaches them.

    Pure logic, no DB calls.
    """
    current = [
        IntervalDesiredItem(
            item=PaymentsSubscriptionDesiredItem(
                stripe_price_id=m.stripe_price_id,
                stripe_item_id=m.stripe_item_id,
                prorate=False,
            ),
            duration_unit=m.duration_unit,
            price=m.price,
        )
        for m in memberships
    ]

    return current + add_intervals


def consolidate_by_price(
    items: list[IntervalDesiredItem],
) -> list[IntervalDesiredItem]:
    """Merge items sharing the same stripe_price_id.

    Sums quantities, picks the stripe_item_id from whichever item has one,
    and resolves prorate by priority:
      new_no_prorate > new_with_prorate > old

    Pure logic, no DB calls.
    """
    groups: dict[str, list[IntervalDesiredItem]] = defaultdict(list)
    for entry in items:
        groups[entry.item.stripe_price_id].append(entry)

    consolidated: list[IntervalDesiredItem] = []
    for _price_id, group in groups.items():
        if len(group) == 1:
            consolidated.append(group[0])
            continue

        consolidated.append(_merge_group(group))

    return consolidated


def _merge_group(group: list[IntervalDesiredItem]) -> IntervalDesiredItem:
    """Merge a group of items with the same stripe_price_id."""
    quantity = sum(e.item.quantity for e in group)
    total_price = sum(e.price for e in group)
    stripe_item_id = group[0].item.stripe_item_id
    prorate = _resolve_prorate(group)

    return IntervalDesiredItem(
        item=PaymentsSubscriptionDesiredItem(
            stripe_price_id=group[0].item.stripe_price_id,
            stripe_item_id=stripe_item_id,
            prorate=prorate,
            quantity=quantity,
        ),
        duration_unit=group[0].duration_unit,
        price=total_price,
    )


def _resolve_prorate(group: list[IntervalDesiredItem]) -> bool:
    """Resolve prorate for a consolidated group by priority.

    Sort order: new_no_prorate > new_with_prorate > old.
    The winner's prorate value is used for the consolidated item.
    """

    def _sort_key(entry: IntervalDesiredItem) -> int:
        is_new = entry.item.stripe_item_id is None
        if is_new and not entry.item.prorate:
            return 0
        if is_new and entry.item.prorate:
            return 1
        return 2

    winner = sorted(group, key=_sort_key)[0]
    return winner.item.prorate


def map_add_ids_to_intervals(
    add_ids: list[SyncItem],
    interval_map: dict[str, tuple[DurationUnit, int]],
) -> list[IntervalDesiredItem]:
    """Map add_ids to IntervalDesiredItems using the interval lookup.

    Items carry no discounts — the sync-time coupon step attaches them.

    Raises:
        ValueError: If a stripe_price_id is not found.
    """
    resolved = []
    for item in add_ids:
        if item.stripe_price_id not in interval_map:
            raise ValueError(
                f"Price not found: {item.stripe_price_id}",
            )
        duration_unit, price = interval_map[item.stripe_price_id]
        resolved.append(
            IntervalDesiredItem(
                item=PaymentsSubscriptionDesiredItem(
                    stripe_price_id=item.stripe_price_id,
                    stripe_item_id=item.stripe_item_id,
                    prorate=item.prorate,
                    quantity=item.quantity,
                ),
                duration_unit=duration_unit,
                price=price,
            )
        )
    return resolved


def build_subscription_bucket(
    desired: list[IntervalDesiredItem],
    existing_sub_id: str | None,
) -> IntervalBucket:
    """Consolidate all desired items into a single subscription bucket.

    All recurring plans are monthly (enforced by DB constraint
    recurring_must_be_monthly), so there is exactly one bucket.

    Consolidates items by price so each stripe_price_id appears
    at most once with the correct quantity.
    Pure logic, no DB calls.
    """
    consolidated = consolidate_by_price(desired)
    return IntervalBucket(
        interval=DurationUnit.month,
        items=[e.item for e in consolidated],
        existing_sub_id=existing_sub_id,
        total_price=sum(e.price for e in consolidated),
    )


# ── Sync-Time Discount Aggregation ──────────────────────────────────


def plan_line_discounts(
    bucket: IntervalBucket,
    snapshots: list[AppliedDiscountSnapshot],
    current_coupon_ids: set[str],
    today: date,
) -> list[LineDiscountPlan]:
    """Compute each consolidated line's per-mode discount plan.

    For every bucket item that carries a stripe_item_id (an existing Stripe
    line), gather the snapshots frozen onto memberships on that line, run the
    end_date exclusion and the ``once``-consumption gate against the live
    Stripe state, then aggregate the survivors per ``discount_mode``:
    ``line_percent = (Σ per-unit percents) / quantity`` and ``line_amount =
    Σ per-unit dollar_offs``. ``once`` and ``ongoing`` never mix into one
    value. New lines (no stripe_item_id yet) are skipped — they get their
    coupon on the next sync once Stripe has assigned an item id.

    Pure logic, no DB or Stripe calls. The caller owns the Stripe coupon
    find-or-create and the snapshot writebacks; this function only decides
    what each line's value is and which snapshots fed / were consumed.
    """
    by_item: dict[str, list[AppliedDiscountSnapshot]] = defaultdict(list)
    for snap in snapshots:
        by_item[snap.stripe_item_id].append(snap)

    plans: list[LineDiscountPlan] = []
    for item in bucket.items:
        if not item.stripe_item_id:
            continue
        line_snaps = by_item.get(item.stripe_item_id, [])
        if not line_snaps:
            continue
        plans.append(
            _plan_one_line(
                stripe_item_id=item.stripe_item_id,
                quantity=item.quantity,
                snapshots=line_snaps,
                current_coupon_ids=current_coupon_ids,
                today=today,
            )
        )
    return plans


def _plan_one_line(
    stripe_item_id: str,
    quantity: int,
    snapshots: list[AppliedDiscountSnapshot],
    current_coupon_ids: set[str],
    today: date,
) -> LineDiscountPlan:
    """Plan the discounts for a single consolidated line."""
    contributing: list[AppliedDiscountSnapshot] = []
    consumed_ids: list[UUID] = []

    for snap in snapshots:
        if _is_past_end_date(snap, today):
            continue
        if _is_consumed_once(snap, current_coupon_ids):
            consumed_ids.append(snap.applied_discount_id)
            continue
        contributing.append(snap)

    values = _aggregate_values(contributing, quantity)
    return LineDiscountPlan(
        stripe_item_id=stripe_item_id,
        values=values,
        consumed_ids=consumed_ids,
    )


def _is_past_end_date(
    snapshot: AppliedDiscountSnapshot,
    today: date,
) -> bool:
    """Whether a snapshot's resolved end_date has passed (exclusive)."""
    return snapshot.end_date is not None and snapshot.end_date <= today


def _is_consumed_once(
    snapshot: AppliedDiscountSnapshot,
    current_coupon_ids: set[str],
) -> bool:
    """Whether a pending ``once`` snapshot has been invoiced (consumed).

    A ``once`` snapshot with a null end_date is consumed once its stored
    stripe_coupon_id is no longer present on the live subscription (Stripe
    already invoiced it). A snapshot with no coupon yet (just applied, never
    synced) is still pending — it has not been attached, so absence does not
    mean consumed.
    """
    if snapshot.discount_mode != DiscountMode.once:
        return False
    if snapshot.end_date is not None:
        return False
    if snapshot.stripe_coupon_id is None:
        return False
    return snapshot.stripe_coupon_id not in current_coupon_ids


def _aggregate_values(
    snapshots: list[AppliedDiscountSnapshot],
    quantity: int,
) -> list[LineDiscountValue]:
    """Aggregate surviving snapshots into at most one value per mode.

    Percents are summed per unit then divided by the line quantity; dollars
    are summed. A mode contributes a value only when it has a non-zero percent
    or dollar total. ``once`` and ``ongoing`` are kept separate, and each value
    carries the ids of the same-mode snapshots that fed it (percent and dollar
    contributors of a mode share the value's writeback set — the deterministic
    coupon for that mode covers whichever value Stripe applies).
    """
    divisor = quantity if quantity > 0 else 1
    values: list[LineDiscountValue] = []
    for mode in (DiscountMode.once, DiscountMode.ongoing):
        mode_snaps = [s for s in snapshots if s.discount_mode == mode]
        if not mode_snaps:
            continue
        mode_ids = [s.applied_discount_id for s in mode_snaps]
        percent_sum = sum(s.percentage_off or 0.0 for s in mode_snaps)
        dollar_sum = sum(s.dollar_off or 0 for s in mode_snaps)

        if percent_sum > 0:
            values.append(
                LineDiscountValue(
                    discount_mode=mode,
                    percentage_off=percent_sum / divisor,
                    contributing_ids=mode_ids,
                )
            )
        if dollar_sum > 0:
            values.append(
                LineDiscountValue(
                    discount_mode=mode,
                    dollar_off=dollar_sum,
                    contributing_ids=mode_ids,
                )
            )
    return values
