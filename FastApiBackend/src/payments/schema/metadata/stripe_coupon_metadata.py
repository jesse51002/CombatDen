"""Metadata for Stripe Coupon resources (gym discounts)."""

from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeCouponMetadata(BaseStripeMetadata):
    """Metadata written onto Stripe Coupon objects.

    Applied on create_discount / update_discount. ``crm_discount_id``
    is the back-reference to the ``gym_discounts`` row.
    """

    crm_discount_id: UUID
    gym_id: UUID
