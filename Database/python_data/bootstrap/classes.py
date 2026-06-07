"""Direct-DB seeding for gym_classes (with embedded scheduling),
class_instance_exceptions, class_range_exceptions, class_history,
and member_attendance.
"""

from __future__ import annotations

import uuid

from constants import CLASSES_PER_GYM
from generators import classes as classes_generator
from schema.gym_class import (
    MemberAttendanceCreate,
    ClassHistoryCreate,
    GymClassCreate,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member import MemberCreate
from schema.member_membership import MemberMembershipCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    gym_name: str,
    employees: list[GymEmployeeCreate],
) -> list[GymClassCreate]:
    classes, instance_exc, range_exc = classes_generator.generate_classes(
        gym_id, CLASSES_PER_GYM, employees
    )
    client.table("gym_classes").insert([c.to_insert_dict() for c in classes]).execute()
    if instance_exc:
        client.table("class_instance_exceptions").insert(
            [e.to_insert_dict() for e in instance_exc]
        ).execute()
    if range_exc:
        client.table("class_range_exceptions").insert(
            [e.to_insert_dict() for e in range_exc]
        ).execute()
    print(
        f"  {gym_name}: {len(classes)} classes, "
        f"{len(instance_exc)} instance exceptions, {len(range_exc)} range exceptions"
    )
    return classes


def create_history_and_attendance(
    client: Client,
    gym_id: uuid.UUID,
    gym_name: str,
    classes: list[GymClassCreate],
    members: list[MemberCreate],
    membership_rows: list[MemberMembershipCreate],
) -> tuple[list[ClassHistoryCreate], list[MemberAttendanceCreate]]:
    history, attendance = classes_generator.generate_class_history_and_attendance(
        gym_id, classes, members, membership_rows
    )
    if history:
        _bulk_insert(client, "class_history", history)
    if attendance:
        _bulk_insert(client, "member_attendance", attendance)
    print(f"  {gym_name}: {len(history)} class instances, {len(attendance)} attendance rows")

    # Update members.last_class from each member's most-recent attendance
    if attendance and history:
        history_by_id = {h.class_history_id: h for h in history}
        latest_by_member: dict[uuid.UUID, str] = {}
        for a in attendance:
            occ = history_by_id[a.class_history_id].occurred_at.isoformat()
            if a.member_id not in latest_by_member or occ > latest_by_member[a.member_id]:
                latest_by_member[a.member_id] = occ
        for member_id, last_ts in latest_by_member.items():
            client.table("members").update({"last_class": last_ts}).eq(
                "member_id", str(member_id)
            ).execute()

    return history, attendance


def _bulk_insert(client: Client, table: str, rows: list) -> None:
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        client.table(table).insert([r.to_insert_dict() for r in batch]).execute()
