"""Metadata for one-time Stripe Invoices created for membership starts."""

from typing import Literal
from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeMembershipOneTimeMetadata(BaseStripeMetadata):
    """Metadata written onto one-time invoices for non-recurring plans.

    Applied by ``member_memberships_start._charge_one_time`` when a
    member starts a one-time (non-recurring) membership plan. The
    invoice has no subscription, so the webhook resolves the user via
    ``crm_user_id`` from metadata rather than by subscription-item
    lookup (gated on ``crm_one_time_payment=True``).
    """

    crm_user_id: UUID
    gym_id: UUID
    plan_id: UUID
    crm_one_time_payment: Literal[True] = True
    type: Literal["membership_one_time"] = "membership_one_time"
    crm_paid_with_cash: bool = False
