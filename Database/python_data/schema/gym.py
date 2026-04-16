from uuid import UUID

from . import SeedModel


class GymCreate(SeedModel):
    gym_id: UUID
    gym_name: str
    gym_description: str | None = None
    stripe_account_id: str | None = None
    stripe_onboarding_status: str = "not_started"
