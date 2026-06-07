from enum import StrEnum
from uuid import UUID

from . import SeedModel


class StripeOnboardingStatus(StrEnum):
    """Mirrors the Postgres `stripe_onboarding_status` enum in gyms.sql."""

    not_started = "not_started"
    pending = "pending"
    complete = "complete"
    disabled = "disabled"


class GymCreate(SeedModel):
    gym_id: UUID
    gym_name: str
    gym_description: str | None = None
    timezone: str = "America/Chicago"
    is_rank_enabled: bool = True
    # Stripe Connect account the backend creates products/customers/
    # subscriptions against on this gym's behalf. UNIQUE per gym.
    stripe_account_id: str | None = None
