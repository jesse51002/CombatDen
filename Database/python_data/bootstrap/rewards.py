"""Direct-DB seeding for gym_rewards and reward redemptions."""

from __future__ import annotations

import uuid

from constants import REWARDS_PER_GYM
from generators import reward_redemptions
from generators import rewards as rewards_generator
from schema.gym_reward import GymRewardCreate
from schema.user_gym_profile import UserGymProfileCreate
from supabase import Client


def create(client: Client, gym_id: uuid.UUID) -> list[GymRewardCreate]:
    gym_rewards = rewards_generator.generate(gym_id, REWARDS_PER_GYM)
    client.table("gym_rewards").insert([r.to_insert_dict() for r in gym_rewards]).execute()
    return gym_rewards


def create_redemptions(
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[UserGymProfileCreate],
    rewards: list[GymRewardCreate],
) -> None:
    redemptions = reward_redemptions.generate(gym_id, profiles, rewards)
    if redemptions:
        client.table("user_gym_reward_redemptions").insert(
            [r.to_insert_dict() for r in redemptions]
        ).execute()
