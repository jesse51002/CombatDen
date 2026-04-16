from uuid import UUID

from . import SeedModel


class GymRewardCreate(SeedModel):
    reward_id: UUID
    gym_id: UUID
    title: str
    amount_off: str | None = None
    image_url: str | None = None
    point_cost: int
    is_active: bool = True
