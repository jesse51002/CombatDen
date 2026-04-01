from typing import Optional
from uuid import UUID

from . import SeedModel


class GymRewardCreate(SeedModel):
    reward_id: UUID
    gym_id: UUID
    title: str
    amount_off: Optional[str] = None
    image_url: Optional[str] = None
    point_cost: int
    is_active: bool = True
