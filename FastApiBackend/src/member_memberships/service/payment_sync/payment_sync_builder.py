"""Pure logic for building desired items and grouping by interval."""

import logging
from collections import defaultdict
from uuid import UUID

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    IntervalBucket,
    IntervalDesiredItem,
    SyncItem,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)

logger = logging.getLogger(__name__)


def aggregate_plan_discounts(
    memberships: list[ActiveMembershipRow],
    coupon_by_discount_id: dict[UUID, str],
) -> dict[UUID, list[SubscriptionItemDiscount]]:
    """Union discounts across members on the same plan, keyed by Stripe coupon.

    Linked accounts sharing a plan get the union of all their
    discounts applied to every item on that plan. CRM ``discount_id``
    values are resolved to real Stripe coupon IDs via
    ``coupon_by_discount_id``.

    If a membership references a ``discount_id`` that is missing from
    the lookup (discount was soft-deleted or its Stripe sync never
    completed), a warning is logged and that discount is skipped.
    The rest of the sync still proceeds — one stale discount should
    not abort the whole subscription update.

    Args:
        memberships: Active recurring memberships for the family.
        coupon_by_discount_id: CRM ``discount_id`` -> Stripe
            ``stripe_coupon_id`` lookup, sourced from
            ``PaymentSyncQueries.get_discount_details``.

    Returns:
        Mapping of ``plan_id`` -> list of ``SubscriptionItemDiscount``,
        deduplicated on the Stripe coupon string.
    """
    plan_discount_ids: dict[UUID, set[UUID]] = defaultdict(set)
    membership_context: dict[UUID, tuple[UUID, UUID]] = {}

    for m in memberships:
        for d in m.discount_ids:
            plan_discount_ids[m.plan_id].add(d)
            membership_context.setdefault(d, (m.plan_id, m.member_id))

    plan_discounts: dict[UUID, list[SubscriptionItemDiscount]] = {}
    for plan_id, discount_ids in plan_discount_ids.items():
        seen_coupons: set[str] = set()
        items: list[SubscriptionItemDiscount] = []
        for discount_id in discount_ids:
            coupon = coupon_by_discount_id.get(discount_id)
            if coupon is None:
                ctx_plan, ctx_user = membership_context.get(
                    discount_id,
                    (plan_id, None),
                )
                logger.warning(
                    "Skipping unresolved discount_id %s on plan %s "
                    "(member_id=%s): no stripe_coupon_id found. "
                    "Discount is likely soft-deleted or never synced "
                    "to Stripe.",
                    discount_id,
                    ctx_plan,
                    ctx_user,
                )
                continue
            if coupon in seen_coupons:
                continue
            seen_coupons.add(coupon)
            items.append(SubscriptionItemDiscount(coupon=coupon))
        plan_discounts[plan_id] = items

    return plan_discounts


def build_desired_items(
    memberships: list[ActiveMembershipRow],
    add_intervals: list[IntervalDesiredItem],
    plan_discounts: dict[UUID, list[SubscriptionItemDiscount]],
) -> list[IntervalDesiredItem]:
    """Convert current memberships + adds into desired items.

    Cancellations must be applied upstream by filtering
    ``memberships`` on the full ``(member_id, plan_id)`` key
    before calling this function — filtering by
    ``stripe_price_id`` alone is unsafe on shared family plans
    where every member row shares the same price.

    Existing memberships get prorate=False (old items).
    New add_ids keep whatever prorate the caller set.

    Args:
        plan_discounts: Pre-aggregated plan-level discounts
            from aggregate_plan_discounts().

    Pure logic, no DB calls.
    """
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
    add_ids: list[SyncItem],
    interval_map: dict[str, tuple[DurationUnit, int]],
    coupon_by_discount_id: dict[UUID, str],
) -> list[IntervalDesiredItem]:
    """Map add_ids to IntervalDesiredItems using the interval lookup.

    Each new item arrives with its CRM ``discount_ids`` resolved
    to Stripe coupon references on the very first sync — no
    dependency on a filtered-view writeback race.

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
        discounts = _resolve_item_discounts(
            item.discount_ids,
            coupon_by_discount_id,
        )
        resolved.append(
            IntervalDesiredItem(
                item=PaymentsSubscriptionDesiredItem(
                    stripe_price_id=item.stripe_price_id,
                    stripe_item_id=item.stripe_item_id,
                    prorate=item.prorate,
                    quantity=item.quantity,
                    discounts=discounts,
                ),
                duration_unit=duration_unit,
                price=price,
            )
        )
    return resolved


def _resolve_item_discounts(
    discount_ids: list[UUID],
    coupon_by_discount_id: dict[UUID, str],
) -> list[SubscriptionItemDiscount]:
    """Resolve CRM discount UUIDs to Stripe coupon references.

    Skips any discount_id missing from the lookup (soft-deleted
    or never synced to Stripe) — one stale discount should not
    abort the whole item.
    """
    seen: set[str] = set()
    resolved: list[SubscriptionItemDiscount] = []
    for discount_id in discount_ids:
        coupon = coupon_by_discount_id.get(discount_id)
        if coupon is None or coupon in seen:
            continue
        seen.add(coupon)
        resolved.append(SubscriptionItemDiscount(coupon=coupon))
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
