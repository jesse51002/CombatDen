"""Create gyms + gym_employees + owner auth users directly in the DB."""

from __future__ import annotations

import uuid

from constants import EXTRA_EMPLOYEES_PER_GYM, NUM_GYMS, STRIPE_TEST_ACCOUNT_ID
from generators import auth, employees, gyms
from schema.gym import GymCreate
from schema.gym_employee import GymEmployeeCreate
from supabase import Client
from utils import make_seeded_uuids


class GymBundle:
    def __init__(
        self,
        gym: GymCreate,
        owner_user: dict,
        owner_employee: GymEmployeeCreate,
        staff_employees: list[GymEmployeeCreate],
    ) -> None:
        self.gym = gym
        self.owner_user = owner_user
        self.owner_employee = owner_employee
        self.staff_employees = staff_employees

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
    owner_ids = make_seeded_uuids(seed=1, count=NUM_GYMS)
    gym_ids = make_seeded_uuids(seed=3, count=NUM_GYMS)
    owner_employee_ids = make_seeded_uuids(seed=4, count=NUM_GYMS)
    staff_employee_ids = make_seeded_uuids(seed=5, count=NUM_GYMS * EXTRA_EMPLOYEES_PER_GYM)

    print("Creating auth users (owners)...")
    owner_users: list[dict] = []
    for i in range(NUM_GYMS):
        user = auth.create_user(client, f"owner{i + 1}@test.com", user_id=owner_ids[i])
        owner_users.append(user)
        print(f"  Owner: {user['email']}")

    print("Creating gyms...")
    gym_records: list[GymCreate] = []
    for i in range(NUM_GYMS):
        # Every seeded gym needs a Stripe Connect account so the backend can
        # create products/customers/subscriptions on its behalf. The column is
        # UNIQUE, so with one shared test account NUM_GYMS is 1.
        gym = gyms.generate(gym_id=gym_ids[i], stripe_account_id=STRIPE_TEST_ACCOUNT_ID)
        gym_records.append(gym)
        print(f"  {gym.gym_name}")
    client.table("gyms").upsert(
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
            )
        )

    return bundles
