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
    pending_ratio: float = 0.3,
) -> None:
    """Seed reward redemptions for a gym.

    pending_ratio: fraction of rows to mint as 'pending' (for CRM approval
    queue testing). Default 0.3 keeps a steady stream of pending rows in the
    CRM approval queue's demo data.

    Every seeded redemption has already debited its member's balance
    (production is debit-on-request), so the post-debit balances are
    written back to the already-inserted member rows — same pattern as
    the classes bootstrap's last_class backfill.

    Must run AFTER the attendance bootstrap: what a member can afford is the
    points their attendance earned them, so `create_attendance` has to have
    awarded and written those balances first.
    """
    rows, debited_balances = redemptions_generator.generate(
        gym_id, members, rewards, pending_ratio=pending_ratio
    )
    if not rows:
        return
    client.table("member_reward_redemptions").insert(
        [r.to_insert_dict() for r in rows]
    ).execute()
    for member_id, balance in debited_balances.items():
        client.table("members").update({"points_balance": balance}).eq(
            "member_id", str(member_id)
        ).execute()
