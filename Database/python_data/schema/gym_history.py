from datetime import date
from uuid import UUID

from . import SeedModel


class GymHistoryCreate(SeedModel):
    gym_id: UUID
    date: date
    members_total: int
    members_churned: int
    members_gained: int
    members_retained: int
    revenue: int
