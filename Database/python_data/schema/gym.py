from uuid import UUID

from . import SeedModel


class GymCreate(SeedModel):
    gym_id: UUID
    gym_name: str
    gym_description: str | None = None
    timezone: str = "America/Chicago"
    is_rank_enabled: bool = True
