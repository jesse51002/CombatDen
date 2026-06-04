"""Metadata for ad-hoc Stripe Invoices (charge-card flow)."""

from typing import Literal
from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeAdHocInvoiceMetadata(BaseStripeMetadata):
    """Metadata written onto ad-hoc invoices from the charge-card flow.

    Applied by ``member_memberships_charge_card`` when a gym owner
    charges a member's card for an arbitrary amount outside any
    membership plan. No plan is in scope; the webhook resolves the
    user via ``member_id`` from metadata (gated on
    ``crm_one_time_payment=True``).
    """

    member_id: UUID
    gym_id: UUID
    crm_one_time_payment: Literal[True] = True
    crm_paid_with_cash: bool = False
