"""Shared model for a member's paying-parent billing profile."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel

from src.shared.gym_timezone import gym_today


class ParentProfile(BaseModel):
    """A payer's billing-profile fields.

    The billing surface of whoever pays (Stripe customer + monthly
    subscription + freeze window). Hydrated two ways by
    ``BillingParentResolver``: ``resolve_parent`` follows the single-level
    account hierarchy to the FAMILY parent; ``resolve_payer`` looks up a
    specific ``paid_by_member_id`` directly (a self-paying linked member's
    own profile). Shared because payer resolution is needed across
    billing-touching services, not just the payment sync.
    """

    member_id: UUID
    gym_id: UUID
    stripe_customer_id: str
    stripe_sub_id_month: str | None = None
    freeze_start_date: date | None = None
    freeze_end_date: date | None = None
    timezone: str = "America/Chicago"

    @property
    def is_frozen(self) -> bool:
        """Whether the parent account is currently in a freeze window."""
        if self.freeze_start_date is None or self.freeze_end_date is None:
            return False
        today = gym_today(self.timezone)
        return self.freeze_start_date <= today <= self.freeze_end_date
