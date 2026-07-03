from uuid import UUID

from . import SeedModel


class GymRewardCreate(SeedModel):
    reward_id: UUID
    gym_id: UUID
    title: str
    # NOT NULL in the DB — every reward has a value badge, e.g. 'Free',
    # '30% off' (the seed always assigns one; the backend fills 'Free'
    # when a writer provides none).
    price_label: str
    # NOT NULL in the DB — every reward has an image (the seed always
    # assigns one; the backend fills a platform default when a writer
    # provides none).
    image_url: str
    point_cost: int
    is_active: bool = True
