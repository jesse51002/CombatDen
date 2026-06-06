"""Shared model for a member's paying-parent billing profile."""

from datetime import date
from uuid import UUID

from pydantic import BaseModel

from src.shared.gym_timezone import gym_today


class ParentProfile(BaseModel):
    """Paying parent's billing-profile fields.

    The single-level account hierarchy resolves any family member to the
    paying parent; this is that parent's billing surface (Stripe customer +
    monthly subscription + freeze window). Shared because parent resolution is
    needed across billing-touching services, not just the payment sync.
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
