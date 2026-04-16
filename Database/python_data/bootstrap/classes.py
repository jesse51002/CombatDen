"""Direct-DB seeding for gym_classes, schedules, exceptions, and logs."""

from __future__ import annotations

import uuid

from constants import CLASSES_PER_GYM
from generators import classes as classes_generator
from schema.gym_class import (
    GymClassCreate,
    GymClassLogCreate,
    GymClassScheduleCreate,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    gym_name: str,
    employees: list[GymEmployeeCreate],
    plans: list[MembershipPlanCreate],
) -> tuple[list[GymClassCreate], list[GymClassScheduleCreate]]:
    """Create classes + schedules + exceptions for a gym. Return (parents, schedules)."""
    parents, schedules, exceptions = classes_generator.generate(
        gym_id, CLASSES_PER_GYM, employees, plans
    )
    client.table("gym_classes").insert([p.to_insert_dict() for p in parents]).execute()
    client.table("gym_class_schedules").insert([s.to_insert_dict() for s in schedules]).execute()
    if exceptions:
        client.table("gym_class_exceptions").insert(
            [e.to_insert_dict() for e in exceptions]
        ).execute()
    print(
        f"  {gym_name}: {len(parents)} classes, "
        f"{len(schedules)} schedules, {len(exceptions)} exceptions"
    )
    return parents, schedules


def create_logs(
    client: Client,
    gym_id: uuid.UUID,
    gym_name: str,
    schedules: list[GymClassScheduleCreate],
    profiles: list[UserGymProfileCreate],
    memberships: list[MemberMembershipCreate],
) -> list[GymClassLogCreate]:
    """Create attendance logs and update profile.last_class."""
    logs = classes_generator.generate_logs(gym_id, schedules, profiles, memberships)
    if logs:
        batch_size = 500
        for i in range(0, len(logs), batch_size):
            batch = logs[i : i + batch_size]
            client.table("gym_classes_log").insert([lg.to_insert_dict() for lg in batch]).execute()
    print(f"  {gym_name}: {len(logs)} log entries")

    # Compute last_class per profile from actual log entries
    latest_by_user: dict[uuid.UUID, str] = {}
    for lg in logs:
        uid = lg.crm_user_id
        ts = lg.time.isoformat()
        if uid not in latest_by_user or ts > latest_by_user[uid]:
            latest_by_user[uid] = ts
    for uid, last_ts in latest_by_user.items():
        client.table("user_gym_profiles").update({"last_class": last_ts}).eq(
            "crm_user_id", str(uid)
        ).execute()

    return logs
