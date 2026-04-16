"""Create gyms + gym_employees directly in the DB.

No backend endpoint exists for these — they're admin-provisioned. The seed
script hits Supabase with the service-role key so RLS is bypassed.

All writes here are idempotent so re-running the seed script is safe:
  - gyms are upserted on gym_id (seeded UUIDs).
  - owner/staff employees use seeded UUIDs so they can be upserted on
    employee_id. Re-runs overwrite the existing row with the same data.
  - auth users fall through to the existing row on the "already exists"
    error from the Supabase admin API (see generators/auth.py).
"""

from __future__ import annotations

import uuid

from constants import (
    EXTRA_EMPLOYEES_PER_GYM,
    LINKED_MEMBERS_PER_GYM,
    NUM_GYMS,
    STRIPE_TEST_ACCOUNT_ID,
)
from generators import auth, employees, gyms
from schema.gym import GymCreate
from schema.gym_employee import GymEmployeeCreate
from supabase import Client
from utils import make_seeded_uuids


class GymBundle:
    """Everything a downstream step needs about one bootstrapped gym."""

    def __init__(
        self,
        gym: GymCreate,
        owner_user: dict,
        owner_employee: GymEmployeeCreate,
        staff_employees: list[GymEmployeeCreate],
        linked_auth_users: list[dict],
    ) -> None:
        self.gym = gym
        self.owner_user = owner_user
        self.owner_employee = owner_employee
        self.staff_employees = staff_employees
        self.linked_auth_users = linked_auth_users

    @property
    def gym_id(self) -> uuid.UUID:
        return self.gym.gym_id

    @property
    def gym_name(self) -> str:
        return self.gym.gym_name

    @property
    def owner_email(self) -> str:
        return self.owner_user["email"]

    @property
    def all_employees(self) -> list[GymEmployeeCreate]:
        return [self.owner_employee] + self.staff_employees


def create_all(client: Client) -> list[GymBundle]:
    """Create auth users, gyms, and employees. Return one bundle per gym."""
    owner_ids = make_seeded_uuids(seed=1, count=NUM_GYMS)
    member_auth_ids = make_seeded_uuids(seed=2, count=NUM_GYMS * LINKED_MEMBERS_PER_GYM)
    gym_ids = make_seeded_uuids(seed=3, count=NUM_GYMS)
    owner_employee_ids = make_seeded_uuids(seed=4, count=NUM_GYMS)
    staff_employee_ids = make_seeded_uuids(seed=5, count=NUM_GYMS * EXTRA_EMPLOYEES_PER_GYM)
    linked_member_emails = [
        f"linked-member-{i + 1}@test.com" for i in range(NUM_GYMS * LINKED_MEMBERS_PER_GYM)
    ]

    print("Creating auth users (owners)...")
    owner_users: list[dict] = []
    for i in range(NUM_GYMS):
        user = auth.create_user(client, f"owner{i + 1}@test.com", user_id=owner_ids[i])
        owner_users.append(user)
        print(f"  Owner: {user['email']}")

    print("Creating auth users (linked member accounts)...")
    linked_auth_by_gym: list[list[dict]] = []
    auth_idx = 0
    for _ in range(NUM_GYMS):
        gym_auth: list[dict] = []
        for _ in range(LINKED_MEMBERS_PER_GYM):
            user = auth.create_user(
                client,
                linked_member_emails[auth_idx],
                user_id=member_auth_ids[auth_idx],
            )
            gym_auth.append(user)
            auth_idx += 1
        linked_auth_by_gym.append(gym_auth)
    print(f"  Created {NUM_GYMS * LINKED_MEMBERS_PER_GYM} linked member auth accounts")

    print("Creating gyms...")
    gym_records: list[GymCreate] = []
    for i in range(NUM_GYMS):
        gym = gyms.generate(gym_id=gym_ids[i], stripe_account_id=STRIPE_TEST_ACCOUNT_ID)
        gym_records.append(gym)
        print(f"  {gym.gym_name}")
    client.table("gyms_unfiltered").upsert(
        [g.to_insert_dict() for g in gym_records], on_conflict="gym_id"
    ).execute()

    print("Creating employees...")
    bundles: list[GymBundle] = []
    for i, gym in enumerate(gym_records):
        owner = employees.generate_owner(
            gym.gym_id,
            owner_users[i]["id"],
            owner_users[i]["email"],
            employee_id=owner_employee_ids[i],
        )
        staff = employees.generate_staff(gym.gym_id, EXTRA_EMPLOYEES_PER_GYM)
        # Pin staff employee_ids to the seeded pool so re-runs upsert instead
        # of inserting a new row on every call.
        for j, s in enumerate(staff):
            s.employee_id = staff_employee_ids[i * EXTRA_EMPLOYEES_PER_GYM + j]
        gym_employees = [owner] + staff
        client.table("gym_employees").upsert(
            [e.to_insert_dict() for e in gym_employees],
            on_conflict="employee_id",
        ).execute()
        print(f"  {gym.gym_name}: 1 owner + {len(staff)} staff")

        bundles.append(
            GymBundle(
                gym=gym,
                owner_user=owner_users[i],
                owner_employee=owner,
                staff_employees=staff,
                linked_auth_users=linked_auth_by_gym[i],
            )
        )

    return bundles
