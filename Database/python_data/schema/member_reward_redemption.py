from datetime import datetime
from uuid import UUID

from . import SeedModel


class MemberRewardRedemptionCreate(SeedModel):
    redemption_id: UUID
    gym_id: UUID
    member_id: UUID
    reward_id: UUID
    point_cost: int
    redeemed_at: datetime | None = None
