from uuid import UUID

from . import SeedModel


class GymRewardCreate(SeedModel):
    reward_id: UUID
    gym_id: UUID
    title: str
    # Member-app reward-card badge, e.g. 'Free', '30% off'.
    price_label: str | None = None
    image_url: str | None = None
    point_cost: int
    is_active: bool = True
