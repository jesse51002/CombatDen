"""Seed orchestrator (post-payment-pivot, direct-DB only).

Flow:
  1. Bootstrap gyms, owner auth users, employees.
  2. Insert global rank_presets (BJJ / MMA / generic ladders).
  3. Per gym: clone a preset into gym_ranks, create members (with
     current_rank_id assigned from that ladder), classes (+ exceptions),
     rewards, class_history + member_attendance, redemptions,
     activities, gym_history rollup.

Everything is direct-DB via the Supabase service-role key. No backend
round-trip and no Stripe calls — the product no longer handles payments.
"""

from __future__ import annotations

import random

from bootstrap import member_active as bs_member_active
from bootstrap import member_status as bs_member_status
from bootstrap import activities as bs_activities
from bootstrap import classes as bs_classes
from bootstrap import gyms as bs_gyms
from bootstrap import history as bs_history
from bootstrap import members as bs_members
from bootstrap import ranks as bs_ranks
from bootstrap import rewards as bs_rewards
from config import get_supabase_client
from constants import SEED
from faker import Faker
from schema.gym_rank import GymType

# Cycle through the three presets across seeded gyms so all paths get exercised.
_GYM_TYPE_CYCLE = [GymType.bjj, GymType.mma, GymType.generic]


def seed() -> None:
    # Pin the PRNGs so every run is deterministic.
    random.seed(SEED)
    Faker.seed(SEED)
    from generators import members as _members_mod

    _members_mod.fake.unique.clear()

    client = get_supabase_client()

    # Phase 1: bootstrap gyms + auth users + employees.
    bundles = bs_gyms.create_all(client)

    # Phase 2: rank presets (global, once).
    print("\nCreating rank presets...")
    bs_ranks.create_presets(client)

    # Phase 3: per-gym data.
    for i, bundle in enumerate(bundles):
        gym_type = _GYM_TYPE_CYCLE[i % len(_GYM_TYPE_CYCLE)]
        print(f"\n=== {bundle.gym_name} ({bundle.gym_id}) — {gym_type.value} ===")

        # Ranks (clone from preset).
        print("Creating gym ranks...")
        ranks = bs_ranks.create_gym_ranks(client, bundle.gym_id, gym_type)
        print(f"  {len(ranks)} ranks")

        # Members (current_rank_id assigned from the cloned ladder).
        print("Creating members...")
        member_seed = bs_members.create(client, bundle.gym_id, ranks)
        members = member_seed.rows
        print(f"  {len(members)} members")

        # member_status periods (trial / full / disabled). Implicit
        # "inactive" for any time not covered by a row.
        print("Creating member status periods...")
        n_status = bs_member_status.create(client, bundle.gym_id, member_seed.plans)
        print(f"  {n_status} status periods")

        # member_active periods (active / inactive engagement state).
        print("Creating member active periods...")
        n_active = bs_member_active.create(client, bundle.gym_id, member_seed.plans)
        print(f"  {n_active} active periods")

        # Classes + exceptions.
        print("Creating classes...")
        classes = bs_classes.create(
            client, bundle.gym_id, bundle.gym_name, bundle.all_employees
        )

        # Rewards.
        print("Creating rewards...")
        gym_rewards = bs_rewards.create(client, bundle.gym_id)

        # Class history (past instances) + attendance.
        print("Creating class history + attendance...")
        bs_classes.create_history_and_attendance(
            client, bundle.gym_id, bundle.gym_name, classes, members
        )

        # Reward redemptions.
        print("Creating reward redemptions...")
        bs_rewards.create_redemptions(client, bundle.gym_id, members, gym_rewards)

        # Member activities.
        print("Creating activities...")
        bs_activities.create(client, bundle.gym_id, members)

        # Gym history rollup.
        print("Creating gym history...")
        bs_history.create(client, bundle.gym_id, member_count=len(members))

    print("\nSeeding complete!")


if __name__ == "__main__":
    seed()
