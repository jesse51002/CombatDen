"""Direct-DB seeding for gym_classes (identity), gym_class_schedules
(append-only schedule versions), class_instance_exceptions,
class_range_exceptions, member_attendance, and class_signups.
"""

from __future__ import annotations

import uuid

from constants import CLASSES_PER_GYM
from generators import classes as classes_generator
from schema.gym_class import (
    ClassInstanceExceptionCreate,
    ClassRangeExceptionCreate,
    ClassSignupCreate,
    GymClassCreate,
    GymClassScheduleCreate,
    MemberAttendanceCreate,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member import MemberCreate
from schema.member_membership import MemberMembershipCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    gym_timezone: str,
    gym_name: str,
    employees: list[GymEmployeeCreate],
) -> tuple[
    list[GymClassCreate],
    list[GymClassScheduleCreate],
    list[ClassInstanceExceptionCreate],
    list[ClassRangeExceptionCreate],
]:
    classes, schedules, instance_exc, range_exc = classes_generator.generate_classes(
        gym_id, gym_timezone, CLASSES_PER_GYM, employees
    )
    client.table("gym_classes").insert([c.to_insert_dict() for c in classes]).execute()
    client.table("gym_class_schedules").insert(
        [s.to_insert_dict() for s in schedules]
    ).execute()
    if instance_exc:
        client.table("class_instance_exceptions").insert(
            [e.to_insert_dict() for e in instance_exc]
        ).execute()
    if range_exc:
        client.table("class_range_exceptions").insert(
            [e.to_insert_dict() for e in range_exc]
        ).execute()
    print(
        f"  {gym_name}: {len(classes)} classes, {len(schedules)} schedule versions, "
        f"{len(instance_exc)} instance exceptions, {len(range_exc)} range exceptions"
    )
    return classes, schedules, instance_exc, range_exc


def create_attendance(
    client: Client,
    gym_id: uuid.UUID,
    gym_timezone: str,
    gym_name: str,
    classes: list[GymClassCreate],
    schedules: list[GymClassScheduleCreate],
    members: list[MemberCreate],
    membership_rows: list[MemberMembershipCreate],
    instance_exceptions: list[ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
) -> tuple[list[GymClassCreate], list[MemberAttendanceCreate]]:
    """Seed member_attendance for the past month. Returns the
    attendance-eligible class subset alongside the rows, so `create_signups`
    can scope its past sign-ups to the exact same occurrences.
    """
    eligible_classes = classes_generator.select_attendance_eligible_classes(classes)
    attendance = classes_generator.generate_attendance(
        gym_id,
        gym_timezone,
        eligible_classes,
        schedules,
        members,
        membership_rows,
        instance_exceptions,
        range_exceptions,
    )
    if attendance:
        _bulk_insert(client, "member_attendance", attendance)
    print(f"  {gym_name}: {len(attendance)} attendance rows")

    # Update members.last_class from each member's most-recent attendance.
    if attendance:
        latest_by_member: dict[uuid.UUID, str] = {}
        for a in attendance:
            occ = a.occurred_at.isoformat()
            if a.member_id not in latest_by_member or occ > latest_by_member[a.member_id]:
                latest_by_member[a.member_id] = occ
        for member_id, last_ts in latest_by_member.items():
            client.table("members").update({"last_class": last_ts}).eq(
                "member_id", str(member_id)
            ).execute()

    return eligible_classes, attendance


def create_signups(
    client: Client,
    gym_id: uuid.UUID,
    gym_timezone: str,
    gym_name: str,
    classes: list[GymClassCreate],
    eligible_classes: list[GymClassCreate],
    schedules: list[GymClassScheduleCreate],
    members: list[MemberCreate],
    attendance: list[MemberAttendanceCreate],
    instance_exceptions: list[ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
) -> list[ClassSignupCreate]:
    """Seed class_signups (reservations) for both past and future occurrences.

    Past sign-ups reuse the already-generated `attendance` rows, scoped to
    the same `eligible_classes` (a realistic signed-up-and-attended /
    no-show / walk-in mix); future sign-ups are sign-ups only -- a future
    occurrence has no attendance yet.
    """
    signups = classes_generator.generate_class_signups(
        gym_id,
        gym_timezone,
        classes,
        eligible_classes,
        schedules,
        members,
        attendance,
        instance_exceptions,
        range_exceptions,
    )
    if signups:
        _bulk_insert(client, "class_signups", signups)
    print(f"  {gym_name}: {len(signups)} class sign-ups")
    return signups


def _bulk_insert(client: Client, table: str, rows: list) -> None:
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        client.table(table).insert([r.to_insert_dict() for r in batch]).execute()
