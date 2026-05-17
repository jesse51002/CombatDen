"""Direct-DB seeding for gym_rewards and member_reward_redemptions."""

from __future__ import annotations

import uuid

from constants import REWARDS_PER_GYM
from generators import redemptions as redemptions_generator
from generators import rewards as rewards_generator
from schema.member import MemberCreate
from schema.gym_reward import GymRewardCreate
from supabase import Client


def create(client: Client, gym_id: uuid.UUID) -> list[GymRewardCreate]:
    gym_rewards = rewards_generator.generate(gym_id, REWARDS_PER_GYM)
    client.table("gym_rewards").insert([r.to_insert_dict() for r in gym_rewards]).execute()
    return gym_rewards


def create_redemptions(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberCreate],
    rewards: list[GymRewardCreate],
) -> None:
    rows = redemptions_generator.generate(gym_id, members, rewards)
    if rows:
        client.table("member_reward_redemptions").insert(
            [r.to_insert_dict() for r in rows]
        ).execute()
