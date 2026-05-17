from datetime import datetime
from uuid import UUID

from . import SeedModel


class MemberActivityCreate(SeedModel):
    member_id: UUID
    gym_id: UUID
    activity_type: str
    activity_info: dict = {}
    time: datetime | None = None
