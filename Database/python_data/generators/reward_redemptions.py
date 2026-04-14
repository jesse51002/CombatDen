import random
import uuid

from schema.gym_reward import GymRewardCreate
from schema.user_gym_profile import UserGymProfileCreate
from schema.user_gym_reward_redemption import UserGymRewardRedemptionCreate
from utils import random_past_datetime


def generate(
    gym_id: uuid.UUID,
    profiles: list[UserGymProfileCreate],
    rewards: list[GymRewardCreate],
    per_member_max: int = 2,
) -> list[UserGymRewardRedemptionCreate]:
    if not rewards:
        return []

    redemptions: list[UserGymRewardRedemptionCreate] = []
    for profile in profiles:
        # ~40% of members have at least one redemption.
        if random.random() > 0.4:
            continue
        count = random.randint(1, per_member_max)
        for _ in range(count):
            reward = random.choice(rewards)
            redemptions.append(
                UserGymRewardRedemptionCreate(
                    redemption_id=uuid.uuid4(),
                    gym_id=gym_id,
                    crm_user_id=profile.crm_user_id,
                    reward_id=reward.reward_id,
                    point_cost=reward.point_cost,
                    redeemed_at=random_past_datetime(180),
                )
            )
    return redemptions
