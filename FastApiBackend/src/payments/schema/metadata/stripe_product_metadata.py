"""Metadata for Stripe Product resources (membership plans)."""

from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeProductMetadata(BaseStripeMetadata):
    """Metadata written onto Stripe Product objects.

    Applied on create_membership / update_membership. One CRM
    ``membership_plan`` row maps to one Stripe Product; ``plan_id``
    is the back-reference.
    """

    plan_id: UUID
    gym_id: UUID
