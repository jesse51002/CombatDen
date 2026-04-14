from datetime import datetime
from typing import Optional
from uuid import UUID

from . import SeedModel


class UserGymRewardRedemptionCreate(SeedModel):
    redemption_id: UUID
    gym_id: UUID
    crm_user_id: UUID
    reward_id: UUID
    point_cost: int
    redeemed_at: Optional[datetime] = None
