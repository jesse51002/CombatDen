from datetime import datetime
from uuid import UUID

from . import SeedModel


class MemberCreate(SeedModel):
    member_id: UUID
    user_id: UUID | None = None
    gym_id: UUID
    last_class: datetime | None = None
    first_name: str
    last_name: str
    email: str | None = None
    points_balance: int = 0
    current_rank_id: UUID | None = None
