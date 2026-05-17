from datetime import date
from uuid import UUID

from . import SeedModel


class GymHistoryCreate(SeedModel):
    gym_id: UUID
    date: date
    total_active: int
    total_inactive: int
    went_inactive: int
    became_active: int
