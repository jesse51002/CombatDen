from uuid import UUID

from . import SeedModel


class GymWaiverCreate(SeedModel):
    waiver_id: UUID
    gym_id: UUID
    name: str
    current_version_id: UUID | None = None
    is_deleted: bool = False
