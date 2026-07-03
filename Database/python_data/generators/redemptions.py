import random
import uuid

from schema.member import MemberCreate
from schema.gym_reward import GymRewardCreate
from schema.member_reward_redemption import MemberRewardRedemptionCreate, RewardRedemptionStatus
from utils import random_past_datetime


def generate(
    gym_id: uuid.UUID,
    members: list[MemberCreate],
    rewards: list[GymRewardCreate],
    per_member_max: int = 2,
    pending_ratio: float = 0.0,
) -> list[MemberRewardRedemptionCreate]:
    """Generate redemption rows for seeding.

    pending_ratio: fraction of generated rows to mint as 'pending' (awaiting
    admin approval). Default 0.0 preserves existing seed semantics — all rows
    are 'approved'. Pass e.g. 0.3 to populate the CRM approval queue for
    testing.
    """
    if not rewards:
        return []
    redemptions: list[MemberRewardRedemptionCreate] = []
    for m in members:
        if random.random() > 0.4:
            continue
        for _ in range(random.randint(1, per_member_max)):
            r = random.choice(rewards)
            status = (
                RewardRedemptionStatus.pending
                if random.random() < pending_ratio
                else RewardRedemptionStatus.approved
            )
            requested_at = random_past_datetime(180)
            # The DB's resolved_matches_status CHECK requires resolved_at to be
            # NULL for pending rows and set for every decided row; the seed
            # writes via the supabase client so it must satisfy the CHECK too.
            resolved_at = None if status == RewardRedemptionStatus.pending else requested_at
            redemptions.append(
                MemberRewardRedemptionCreate(
                    redemption_id=uuid.uuid4(),
                    gym_id=gym_id,
                    member_id=m.member_id,
                    reward_id=r.reward_id,
                    point_cost=r.point_cost,
                    requested_at=requested_at,
                    status=status,
                    resolved_at=resolved_at,
                )
            )
    return redemptions
