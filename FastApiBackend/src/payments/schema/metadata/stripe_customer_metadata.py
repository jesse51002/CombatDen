"""Metadata for Stripe Customer resources."""

from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeCustomerMetadata(BaseStripeMetadata):
    """Metadata written onto Stripe Customer objects.

    Applied on create_customer / update_customer. Stripe stores these
    keys on the customer record so we can correlate an incoming Stripe
    event back to our CRM rows.
    """

    crm_user_id: UUID
    gym_id: UUID
