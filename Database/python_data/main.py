import uuid

from faker import Faker

from config import get_supabase_client
from constants import (
    ACTIVITIES_PER_MEMBER,
    DISCOUNTS_PER_GYM,
    HISTORY_DAYS,
    LINKED_MEMBERS_PER_GYM,
    MEMBERS_PER_GYM,
    NUM_GYMS,
    PLANS_PER_GYM,
    REWARDS_PER_GYM,
    TRANSACTIONS_PER_MEMBER,
)
from generators import (
    activities,
    auth,
    discounts,
    gyms,
    history,
    memberships,
    plans,
    profiles,
    rewards,
    transactions,
)
from schema.gym import GymCreate
from schema.gym_discount import GymDiscountCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate

fake = Faker()


def seed():
    client = get_supabase_client()

    # Phase 1: Create auth users
    print("Creating auth users...")
    owner_users = []
    for i in range(NUM_GYMS):
        user = auth.create_user(client, f"owner{i + 1}@test.com")
        owner_users.append(user)
        print(f"  Owner: {user['email']}")

    member_auth_users = []
    for _ in range(NUM_GYMS * LINKED_MEMBERS_PER_GYM):
        user = auth.create_user(client, fake.unique.email())
        member_auth_users.append(user)
    print(f"  Created {len(member_auth_users)} member auth accounts")

    # Phase 2: Create gyms
    print("Creating gyms...")
    gym_records: list[GymCreate] = []
    for owner in owner_users:
        gym = gyms.generate(owner["id"])
        gym_records.append(gym)
        print(f"  {gym.gym_name} ({gym.rank_preset})")
    client.table("gyms").insert([g.to_insert_dict() for g in gym_records]).execute()

    # Phase 3: Create profiles
    print("Creating member profiles...")
    all_profiles: dict[uuid.UUID, list[UserGymProfileCreate]] = {}
    auth_idx = 0
    for gym in gym_records:
        gym_profiles = []
        for j in range(MEMBERS_PER_GYM):
            user_id = None
            if j < LINKED_MEMBERS_PER_GYM:
                user_id = member_auth_users[auth_idx]["id"]
                auth_idx += 1
            gym_profiles.append(profiles.generate(gym.gym_id, user_id))
        all_profiles[gym.gym_id] = gym_profiles
        client.table("user_gym_profiles").insert(
            [p.to_insert_dict() for p in gym_profiles]
        ).execute()
    print(f"  Created {NUM_GYMS * MEMBERS_PER_GYM} profiles")

    # Phase 4: Plans, discounts, rewards
    print("Creating plans, discounts, rewards...")
    all_plans: dict[uuid.UUID, list[MembershipPlanCreate]] = {}
    all_discounts: dict[uuid.UUID, list[GymDiscountCreate]] = {}
    for gym in gym_records:
        gym_plans = plans.generate(gym.gym_id, PLANS_PER_GYM)
        all_plans[gym.gym_id] = gym_plans
        client.table("membership_plans").insert(
            [p.to_insert_dict() for p in gym_plans]
        ).execute()

        gym_discounts = discounts.generate(gym.gym_id, DISCOUNTS_PER_GYM)
        all_discounts[gym.gym_id] = gym_discounts
        client.table("gym_discounts").insert(
            [d.to_insert_dict() for d in gym_discounts]
        ).execute()

        gym_rewards = rewards.generate(gym.gym_id, REWARDS_PER_GYM)
        client.table("gym_rewards").insert(
            [r.to_insert_dict() for r in gym_rewards]
        ).execute()

    # Phase 5: Memberships
    print("Creating memberships...")
    for gym in gym_records:
        gym_memberships = memberships.generate(
            all_profiles[gym.gym_id],
            all_plans[gym.gym_id],
            all_discounts[gym.gym_id],
        )
        client.table("member_memberships").insert(
            [m.to_insert_dict() for m in gym_memberships]
        ).execute()

    # Phase 6: Activities and transactions
    print("Creating activities and transactions...")
    for gym in gym_records:
        for profile in all_profiles[gym.gym_id]:
            acts = activities.generate(
                profile.crm_user_id, gym.gym_id, ACTIVITIES_PER_MEMBER
            )
            client.table("user_activities").insert(
                [a.to_insert_dict() for a in acts]
            ).execute()

            txns = transactions.generate(
                profile.crm_user_id, gym.gym_id, all_plans[gym.gym_id],
                TRANSACTIONS_PER_MEMBER,
            )
            client.table("user_gym_transactions").insert(
                [t.to_insert_dict() for t in txns]
            ).execute()

    # Phase 7: Gym history
    print("Creating gym history...")
    for gym in gym_records:
        gym_history = history.generate(
            gym.gym_id, len(all_profiles[gym.gym_id]), HISTORY_DAYS
        )
        client.table("gym_history").insert(
            [h.to_insert_dict() for h in gym_history]
        ).execute()

    print("\nSeeding complete!")


if __name__ == "__main__":
    seed()
