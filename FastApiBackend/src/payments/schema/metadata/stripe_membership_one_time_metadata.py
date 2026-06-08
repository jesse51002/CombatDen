"""Metadata for one-time Stripe Invoices created for membership starts."""

from typing import Literal
from uuid import UUID

from src.payments.schema.metadata.stripe_metadata_base import (
    BaseStripeMetadata,
)


class StripeMembershipOneTimeMetadata(BaseStripeMetadata):
    """Metadata written onto the one-time invoice for non-recurring plans.

    Applied at the **invoice level** when a one-time (non-recurring)
    membership is started. The invoice has no subscription, so the webhook
    resolves the bill owner via ``member_id`` from metadata rather than by
    subscription-item lookup (gated on ``crm_one_time_payment=True``).

    ``member_id`` is the bill OWNER (the paying member). ``plan_id`` is the
    plan for a single-membership invoice; on a CONSOLIDATED invoice that bills
    several family memberships across different plans it is ``None`` (no single
    plan) and ``member_id`` is the payer. It is set once at invoice creation and
    read once on ``invoice.paid`` — never a mutable per-line match key (each
    line maps to its membership via the returned line id, not metadata).
    """

    member_id: UUID
    gym_id: UUID
    plan_id: UUID | None = None
    crm_one_time_payment: Literal[True] = True
    type: Literal["membership_one_time"] = "membership_one_time"
    crm_paid_with_cash: bool = False
