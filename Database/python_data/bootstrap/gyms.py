"""Create gyms + gym_employees + auth users directly in the DB.

Access is granted purely by a verified Supabase auth account whose email
matches a gym_employees row's email (compared lowercase) — there is no more
user_id FK. So every employee who should be able to log in gets a real auth
user (via `generators.auth.create_user`, email_confirm=True) whose email is
stamped onto the employee row it corresponds to; an employee row with no
matching auth user (the "pending" trainer) simply has no login.
"""

from __future__ import annotations

import uuid

from constants import EXTRA_EMPLOYEES_PER_GYM, NUM_GYMS, STRIPE_TEST_ACCOUNT_ID
from generators import auth, employees, gyms
from schema.gym import GymCreate
from schema.gym_employee import EmployeeType, GymEmployeeCreate
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
    admin_ids = make_seeded_uuids(seed=6, count=NUM_GYMS)
    front_desk_ids = make_seeded_uuids(seed=7, count=NUM_GYMS)
    trainer_ids = make_seeded_uuids(seed=8, count=NUM_GYMS)
    gym_ids = make_seeded_uuids(seed=3, count=NUM_GYMS)
    owner_employee_ids = make_seeded_uuids(seed=4, count=NUM_GYMS)
    staff_employee_ids = make_seeded_uuids(seed=5, count=NUM_GYMS * EXTRA_EMPLOYEES_PER_GYM)

    print("Creating auth users (owners)...")
    owner_users: list[dict] = []
    for i in range(NUM_GYMS):
        user = auth.create_user(client, f"owner{i + 1}@test.com", user_id=owner_ids[i])
        owner_users.append(user)
        print(f"  Owner: {user['email']}")

    # Deterministic staff roles so every employee_type + account-state combo
    # is a real, addressable seeded login for backend role-matrix tests. The
    # pending trainer deliberately gets NO auth user.
    print("Creating auth users (admin / front_desk / trainer)...")
    admin_users: list[dict] = []
    front_desk_users: list[dict] = []
    trainer_users: list[dict] = []
    for i in range(NUM_GYMS):
        admin_user = auth.create_user(
            client, f"admin{i + 1}@test.com", user_id=admin_ids[i]
        )
        admin_users.append(admin_user)
        front_desk_user = auth.create_user(
            client, f"frontdesk{i + 1}@test.com", user_id=front_desk_ids[i]
        )
        front_desk_users.append(front_desk_user)
        trainer_user = auth.create_user(
            client, f"trainer{i + 1}@test.com", user_id=trainer_ids[i]
        )
        trainer_users.append(trainer_user)
        print(
            f"  Admin: {admin_user['email']}, "
            f"Front desk: {front_desk_user['email']}, "
            f"Trainer: {trainer_user['email']}"
        )

    print("Creating gyms...")
    gym_records: list[GymCreate] = []
    for i in range(NUM_GYMS):
        # Every seeded gym needs a Stripe Connect account so the backend can
        # create products/customers/subscriptions on its behalf. The column is
        # UNIQUE, so with one shared test account NUM_GYMS is 1.
        gym = gyms.generate(
            gym_id=gym_ids[i], stripe_account_id=STRIPE_TEST_ACCOUNT_ID, index=i
        )
        gym_records.append(gym)
        print(f"  {gym.gym_name}")
    client.table("gyms").upsert(
        [g.to_insert_dict() for g in gym_records], on_conflict="gym_id"
    ).execute()

    print("Creating employees...")
    bundles: list[GymBundle] = []
    for i, gym in enumerate(gym_records):
        # generate_owner / generate_accounted set the employee row's email to
        # the SAME address the matching auth user was just created with — the
        # match is purely by (lowercased) email now, there is no user_id FK.
        owner = employees.generate_owner(
            gym.gym_id,
            owner_users[i]["email"],
            employee_id=owner_employee_ids[i],
        )
        staff = [
            employees.generate_accounted(
                gym.gym_id, admin_users[i]["email"], EmployeeType.admin
            ),
            employees.generate_accounted(
                gym.gym_id, front_desk_users[i]["email"], EmployeeType.front_desk
            ),
            employees.generate_accounted(
                gym.gym_id, trainer_users[i]["email"], EmployeeType.trainer
            ),
            # No verified auth account — exercises the pending / no-account
            # state and legacy account-less instructor data.
            employees.generate_pending_trainer(
                gym.gym_id, f"pending-trainer{i + 1}@test.com"
            ),
        ]
        for j, s in enumerate(staff):
            s.employee_id = staff_employee_ids[i * EXTRA_EMPLOYEES_PER_GYM + j]
        gym_employees = [owner] + staff
        client.table("gym_employees").upsert(
            [e.to_insert_dict() for e in gym_employees],
            on_conflict="employee_id",
        ).execute()
        print(
            f"  {gym.gym_name}: 1 owner + {len(staff)} staff "
            "(admin, front_desk, trainer, pending trainer)"
        )

        bundles.append(
            GymBundle(
                gym=gym,
                owner_user=owner_users[i],
                owner_employee=owner,
                staff_employees=staff,
            )
        )

    return bundles
