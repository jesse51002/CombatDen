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
    resolves attribution from this metadata rather than by
    subscription-item lookup (gated on ``crm_one_time_payment=True``):

    - ``paid_by_member_id`` — the payer whose Stripe customer/card was
      billed (the bill owner of this consolidated invoice).
    - ``paid_for`` — the beneficiaries: the distinct owners of the
      membership(s) on the invoice (a parent paying for several family
      memberships lists each child). Rides as a JSON-array string.

    ``plan_id`` is the plan for a single-membership invoice; on a
    CONSOLIDATED invoice that bills several family memberships across
    different plans it is ``None`` (no single plan). It is set once at
    invoice creation and read once on ``invoice.paid`` — never a mutable
    per-line match key (each line maps to its membership via the returned
    line id, not metadata).
    """

    paid_by_member_id: UUID
    paid_for: list[UUID]
    gym_id: UUID
    plan_id: UUID | None = None
    crm_one_time_payment: Literal[True] = True
    type: Literal["membership_one_time"] = "membership_one_time"
    crm_paid_with_cash: bool = False
