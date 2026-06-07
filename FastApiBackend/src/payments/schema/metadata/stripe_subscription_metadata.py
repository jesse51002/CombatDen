"""Metadata for Stripe Subscription resources."""

from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeSubscriptionMetadata(BaseStripeMetadata):
    """Metadata written onto Stripe Subscription objects.

    Applied on subscription create / update / freeze / unfreeze /
    migration. ``crm_paid_with_cash`` flips to ``True`` when the
    subscription's open invoice is marked paid out of band (see
    ``pay_open_subscription_invoice_out_of_band`` and
    ``_pay_first_invoice_out_of_band``). The webhook reads this to set
    ``payment_method_type='cash'`` on the CRM charge row and to bypass
    the ``stripe_charge_id IS NOT NULL`` guard.
    """

    member_id: UUID
    gym_id: UUID
    crm_paid_with_cash: bool = False
