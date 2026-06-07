"""Metadata for Stripe Price resources."""

from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripePriceMetadata(BaseStripeMetadata):
    """Metadata written onto Stripe Price objects.

    Applied on create_price. Carries both the CRM price row id and
    the owning plan id so price-writeback webhooks can look up either.
    """

    crm_price_id: UUID
    plan_id: UUID
    gym_id: UUID
