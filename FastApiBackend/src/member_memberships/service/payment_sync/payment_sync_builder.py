"""Pure logic for building desired items and grouping by interval."""

from collections import defaultdict
from uuid import UUID

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    IntervalBucket,
    IntervalDesiredItem,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)


def aggregate_plan_discounts(
    memberships: list[ActiveMembershipRow],
) -> dict[UUID, list[SubscriptionItemDiscount]]:
    """Union all discount_ids across members on the same plan.

    Linked accounts sharing a plan get the union of all their
    discounts applied to every item on that plan.

    Returns:
        Mapping of plan_id -> deduplicated list of item discounts.
    """
    plan_discount_ids: dict[UUID, set[UUID]] = defaultdict(set)

    for m in memberships:
        for d in m.discount_ids:
            plan_discount_ids[m.plan_id].add(d)

    return {
        plan_id: [SubscriptionItemDiscount(coupon=str(d)) for d in discount_ids]
        for plan_id, discount_ids in plan_discount_ids.items()
    }


def build_desired_items(
    memberships: list[ActiveMembershipRow],
    add_intervals: list[IntervalDesiredItem],
    cancel_ids: list[PaymentsSubscriptionDesiredItem],
    plan_discounts: dict[UUID, list[SubscriptionItemDiscount]],
) -> list[IntervalDesiredItem]:
    """Convert current memberships + adds - cancels into desired items.

    Existing memberships get prorate=False (old items).
    New add_ids keep whatever prorate the caller set.

    Args:
        plan_discounts: Pre-aggregated plan-level discounts
            from aggregate_plan_discounts().

    Pure logic, no DB calls.
    """
    cancel_price_ids = {c.stripe_price_id for c in cancel_ids}

    current = [
        IntervalDesiredItem(
            item=PaymentsSubscriptionDesiredItem(
                stripe_price_id=m.stripe_price_id,
                stripe_item_id=m.stripe_item_id,
                prorate=False,
                discounts=plan_discounts.get(m.plan_id, []),
            ),
            duration_unit=m.duration_unit,
            price=m.price,
        )
        for m in memberships
        if m.stripe_price_id not in cancel_price_ids
    ]

    return current + add_intervals


def consolidate_by_price(
    items: list[IntervalDesiredItem],
) -> list[IntervalDesiredItem]:
    """Merge items sharing the same stripe_price_id.

    Sums quantities, unions discounts, picks the stripe_item_id
    from whichever item has one, and resolves prorate by priority:
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
    discounts = _union_discounts(group)

    return IntervalDesiredItem(
        item=PaymentsSubscriptionDesiredItem(
            stripe_price_id=group[0].item.stripe_price_id,
            stripe_item_id=stripe_item_id,
            prorate=prorate,
            quantity=quantity,
            discounts=discounts,
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


def _union_discounts(
    group: list[IntervalDesiredItem],
) -> list[SubscriptionItemDiscount]:
    """Deduplicate discounts across all items in the group."""
    seen: set[str] = set()
    unique: list[SubscriptionItemDiscount] = []
    for entry in group:
        for d in entry.item.discounts:
            if d.coupon not in seen:
                seen.add(d.coupon)
                unique.append(d)
    return unique


def map_add_ids_to_intervals(
    add_ids: list[PaymentsSubscriptionDesiredItem],
    interval_map: dict[str, tuple[DurationUnit, int]],
) -> list[IntervalDesiredItem]:
    """Map add_ids to IntervalDesiredItems using the interval lookup.

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
                item=item,
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
