from datetime import datetime
from uuid import UUID

from . import SeedModel


class UserActivityCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    activity_type: str
    activity_info: dict = {}
    time: datetime | None = None
