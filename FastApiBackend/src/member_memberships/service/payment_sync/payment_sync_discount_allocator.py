"""Linked discount allocation across billing interval buckets."""

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    IntervalBucket,
    LinkedDiscountInfo,
)
from src.payments.schema.payments_members_schema import (
    SubscriptionItemDiscount,
)

INTERVAL_PRIORITY = [DurationUnit.week, DurationUnit.month, DurationUnit.year]


def allocate_linked_discounts(
    buckets: dict[DurationUnit, IntervalBucket],
    linked_discounts: list[LinkedDiscountInfo],
) -> None:
    """Assign linked discounts to interval buckets.

    Lowest interval first (week -> month -> year).
    Spills overflow to the next interval up.
    Mutates buckets in-place.
    """
    if not linked_discounts:
        return

    active_intervals = [i for i in INTERVAL_PRIORITY if i in buckets and buckets[i].items]
    if not active_intervals:
        return

    remaining = list(linked_discounts)

    for interval in active_intervals:
        if not remaining:
            break
        remaining = _assign_to_bucket(buckets[interval], remaining)

    if remaining and active_intervals:
        _force_assign_remaining(
            buckets[active_intervals[-1]],
            remaining,
        )


def _assign_to_bucket(
    bucket: IntervalBucket,
    discounts: list[LinkedDiscountInfo],
) -> list[LinkedDiscountInfo]:
    """Assign as many discounts as fit within the bucket's total.

    Returns discounts that didn't fit (overflow).
    """
    bucket_total = bucket.total_price
    running_total = 0
    overflow: list[LinkedDiscountInfo] = []

    for discount in discounts:
        if running_total < bucket_total:
            bucket.subscription_discounts.append(
                SubscriptionItemDiscount(coupon=discount.stripe_coupon_id),
            )
            running_total += discount.dollar_off
        else:
            overflow.append(discount)

    return overflow


def _force_assign_remaining(
    bucket: IntervalBucket,
    discounts: list[LinkedDiscountInfo],
) -> None:
    """Force-assign leftover discounts to the last active bucket."""
    for discount in discounts:
        bucket.subscription_discounts.append(
            SubscriptionItemDiscount(coupon=discount.stripe_coupon_id),
        )
