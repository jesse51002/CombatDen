import uuid

from faker import Faker

from config import get_supabase_client
from utils import make_seeded_uuids
from constants import (
    ACTIVITIES_PER_MEMBER,
    DISCOUNTS_PER_GYM,
    EXTRA_EMPLOYEES_PER_GYM,
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
    employees,
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

    # Generate deterministic IDs (each category has its own seed so they're independent)
    owner_ids = make_seeded_uuids(seed=1, count=NUM_GYMS)
    member_auth_ids = make_seeded_uuids(seed=2, count=NUM_GYMS * LINKED_MEMBERS_PER_GYM)
    gym_ids = make_seeded_uuids(seed=3, count=NUM_GYMS)
    profile_ids = make_seeded_uuids(seed=4, count=NUM_GYMS * MEMBERS_PER_GYM)

    # Phase 1: Create auth users
    print("Creating auth users...")
    owner_users = []
    for i in range(NUM_GYMS):
        user = auth.create_user(client, f"owner{i + 1}@test.com", user_id=owner_ids[i])
        owner_users.append(user)
        print(f"  Owner: {user['email']}")

    member_auth_users = []
    for i in range(NUM_GYMS * LINKED_MEMBERS_PER_GYM):
        user = auth.create_user(client, fake.unique.email(), user_id=member_auth_ids[i])
        member_auth_users.append(user)
    print(f"  Created {len(member_auth_users)} member auth accounts")

    # Phase 2: Create gyms
    print("Creating gyms...")
    gym_records: list[GymCreate] = []
    for i in range(NUM_GYMS):
        gym = gyms.generate(gym_id=gym_ids[i])
        gym_records.append(gym)
        print(f"  {gym.gym_name}")
    client.table("gyms").insert([g.to_insert_dict() for g in gym_records]).execute()

    # Phase 2.5: Create employees (owner + extra staff per gym)
    print("Creating employees...")
    for i, gym in enumerate(gym_records):
        owner_employee = employees.generate_owner(gym.gym_id, owner_users[i]["id"], owner_users[i]["email"])
        staff = employees.generate_staff(gym.gym_id, EXTRA_EMPLOYEES_PER_GYM)
        all_employees = [owner_employee] + staff
        client.table("gym_employees").insert(
            [e.to_insert_dict() for e in all_employees]
        ).execute()
        print(f"  {gym.gym_name}: 1 owner + {len(staff)} staff")

    # Phase 3: Generate profiles (insert deferred until after linking)
    print("Generating member profiles...")
    all_profiles: dict[uuid.UUID, list[UserGymProfileCreate]] = {}
    auth_idx = 0
    profile_idx = 0
    for gym in gym_records:
        gym_profiles = []
        for j in range(MEMBERS_PER_GYM):
            user_id = None
            if j < LINKED_MEMBERS_PER_GYM:
                user_id = member_auth_users[auth_idx]["id"]
                auth_idx += 1
            gym_profiles.append(
                profiles.generate(gym.gym_id, crm_user_id=profile_ids[profile_idx], user_id=user_id)
            )
            profile_idx += 1
        all_profiles[gym.gym_id] = gym_profiles
    print(f"  Generated {NUM_GYMS * MEMBERS_PER_GYM} profiles")

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

    # Phase 5: Memberships + linked account assignment
    print("Creating memberships and linking accounts...")
    all_memberships: dict[uuid.UUID, list] = {}
    for gym in gym_records:
        gym_memberships, link_pairs = memberships.generate(
            all_profiles[gym.gym_id],
            all_plans[gym.gym_id],
            all_discounts[gym.gym_id],
        )
        all_memberships[gym.gym_id] = gym_memberships

        # Apply link pairs to profiles
        profile_map = {p.crm_user_id: p for p in all_profiles[gym.gym_id]}
        for linked_id, primary_id in link_pairs:
            profile_map[linked_id].account_linked_to_id = primary_id

    # Now insert profiles (without account_linked_to_id first, then update linked ones)
    print("Inserting profiles...")
    for gym in gym_records:
        gym_profiles = all_profiles[gym.gym_id]
        # Insert all profiles without links
        insert_dicts = []
        for p in gym_profiles:
            d = p.to_insert_dict()
            d.pop("account_linked_to_id", None)
            insert_dicts.append(d)
        client.table("user_gym_profiles").insert(insert_dicts).execute()

        # Update linked profiles with their account_linked_to_id
        for p in gym_profiles:
            if p.account_linked_to_id is not None:
                client.table("user_gym_profiles").update(
                    {"account_linked_to_id": str(p.account_linked_to_id)}
                ).eq("crm_user_id", str(p.crm_user_id)).execute()
    print(f"  Created {NUM_GYMS * MEMBERS_PER_GYM} profiles")

    # Insert memberships
    print("Inserting memberships...")
    for gym in gym_records:
        client.table("member_memberships").insert(
            [m.to_insert_dict() for m in all_memberships[gym.gym_id]]
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
