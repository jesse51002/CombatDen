"""Linked discount allocation for the subscription bucket."""

from src.member_memberships.schema.payment_sync_schema import (
    IntervalBucket,
    LinkedDiscountInfo,
)
from src.payments.schema.payments_members_schema import (
    SubscriptionItemDiscount,
)


def allocate_linked_discounts(
    bucket: IntervalBucket,
    linked_discounts: list[LinkedDiscountInfo],
) -> None:
    """Assign linked discounts to the subscription bucket.

    All recurring plans are monthly, so there is a single bucket.
    All discounts are assigned directly — no spillover logic needed.

    Mutates bucket in-place.
    """
    if not linked_discounts or not bucket.items:
        return

    for discount in linked_discounts:
        bucket.subscription_discounts.append(
            SubscriptionItemDiscount(coupon=discount.stripe_coupon_id),
        )
