from typing import Optional
from uuid import UUID

from . import SeedModel


class GymCreate(SeedModel):
    gym_id: UUID
    gym_name: str
    gym_description: Optional[str] = None
    stripe_account_id: Optional[str] = None
    stripe_onboarding_status: str = "not_started"
