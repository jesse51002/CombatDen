from uuid import UUID

from . import SeedModel


class GymWaiverVersionCreate(SeedModel):
    version_id: UUID
    waiver_id: UUID
    gym_id: UUID
    version_number: int
    body: str
    content_hash: str
