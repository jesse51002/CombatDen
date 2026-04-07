from enum import StrEnum


class StripeCouponDuration(StrEnum):
    """Stripe coupon duration type."""

    once = "once"
    repeating = "repeating"
    forever = "forever"


class StripeResourceType(StrEnum):
    """Type of Stripe resource for error reporting."""

    customer = "customer"
    subscription = "subscription"
    subscription_item = "subscription_item"
    price = "price"
    product = "product"
    coupon = "coupon"
