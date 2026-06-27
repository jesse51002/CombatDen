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
    membership plan. No plan is in scope; the webhook resolves
    attribution straight from this metadata (gated on
    ``crm_one_time_payment=True``):

    - ``paid_by_member_id`` — the payer whose Stripe customer/card was
      billed (the member themselves or their linked parent).
    - ``paid_for`` — the beneficiaries the charge was FOR (usually just
      ``[payer]``; a charge for someone else lists that member). Rides
      as a JSON-array string (Stripe metadata is string-only).
    """

    paid_by_member_id: UUID
    paid_for: list[UUID]
    gym_id: UUID
    crm_one_time_payment: Literal[True] = True
    crm_paid_with_cash: bool = False
