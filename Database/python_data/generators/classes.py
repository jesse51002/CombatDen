"""Generators for gym_classes (with embedded scheduling), exceptions,
class_history (past class instances), and member_attendance."""

from __future__ import annotations

import random
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta
from typing import NamedTuple
from uuid import UUID

from schema.gym_class import (
    MemberAttendanceCreate,
    ClassHistoryCreate,
    ClassInstanceExceptionCreate,
    ClassRangeExceptionCreate,
    GymClassCreate,
    RecurringUnit,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member import MemberCreate
from schema.member_membership import MemberMembershipCreate

CLASS_TEMPLATES = [
    {"class_name": "Morning BJJ", "class_description": "Fundamentals and sparring for all levels.", "duration_minutes": 60},
    {"class_name": "Evening MMA", "class_description": "Mixed martial arts striking and grappling.", "duration_minutes": 90},
    {"class_name": "Kickboxing", "class_description": "High-energy kickboxing cardio and technique.", "duration_minutes": 60},
    {"class_name": "Open Mat", "class_description": "Free training time with open sparring.", "duration_minutes": 120},
    {"class_name": "Wrestling", "class_description": "Takedowns, control, and scrambles.", "duration_minutes": 60},
    {"class_name": "Muay Thai", "class_description": "Traditional Thai boxing with pads and bags.", "duration_minutes": 75},
    {"class_name": "No-Gi Grappling", "class_description": "Submission grappling without the gi.", "duration_minutes": 60},
    {"class_name": "Kids Martial Arts", "class_description": "Fun and discipline-focused class for ages 6-12.", "duration_minutes": 45},
    {"class_name": "Competition Team", "class_description": "Advanced training for competitors.", "duration_minutes": 90},
    {"class_name": "Strength & Conditioning", "class_description": "Athletic performance training.", "duration_minutes": 60},
]

DAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]


def generate_classes(
    gym_id: uuid.UUID,
    count: int,
    employees: list[GymEmployeeCreate],
) -> tuple[
    list[GymClassCreate],
    list[ClassInstanceExceptionCreate],
    list[ClassRangeExceptionCreate],
]:
    """Build classes (with embedded schedule) plus a few exceptions per gym."""
    templates = random.sample(CLASS_TEMPLATES, min(count, len(CLASS_TEMPLATES)))
    trainer_ids = [e.employee_id for e in employees]

    classes: list[GymClassCreate] = []
    instance_exceptions: list[ClassInstanceExceptionCreate] = []
    range_exceptions: list[ClassRangeExceptionCreate] = []

    for tmpl in templates:
        class_id = uuid.uuid4()

        hour = random.randint(6, 20)
        minute = random.choice([0, 15, 30, 45])
        recurring_unit = random.choices(
            [RecurringUnit.weekly, RecurringUnit.daily, RecurringUnit.monthly],
            weights=[80, 10, 10],
        )[0]

        day_flags = {d: False for d in DAYS}
        if recurring_unit == RecurringUnit.daily:
            day_flags = {d: True for d in DAYS}
        elif recurring_unit == RecurringUnit.weekly:
            num_days = random.randint(2, 5)
            for d in random.sample(DAYS, num_days):
                day_flags[d] = True

        instructor_kwargs: dict = {}
        for d in DAYS:
            if day_flags[d] and trainer_ids and random.random() < 0.8:
                instructor_kwargs[f"{d}_instructor_id"] = random.choice(trainer_ids)

        max_capacity = random.choice([10, 15, 20, 25, 30]) if random.random() < 0.7 else None
        start_date = date.today() - timedelta(days=random.randint(60, 200))
        is_active = random.random() < 0.85

        classes.append(
            GymClassCreate(
                class_id=class_id,
                gym_id=gym_id,
                class_name=tmpl["class_name"],
                class_description=tmpl["class_description"],
                max_capacity=max_capacity,
                points_worth=random.choice([25, 50, 75, 100]),
                is_active=is_active,
                class_time=time(hour, minute),
                duration_minutes=tmpl["duration_minutes"],
                recurring_unit=recurring_unit,
                recurring_interval=1,
                start_date=start_date,
                **day_flags,
                **instructor_kwargs,
            )
        )

        # ~30% of classes get 1-2 single-instance exceptions
        if random.random() < 0.3:
            used_dates: set[date] = set()
            for _ in range(random.randint(1, 2)):
                exc_date = start_date + timedelta(days=random.randint(0, 60))
                if exc_date in used_dates:
                    continue
                used_dates.add(exc_date)

                cancelled = random.random() < 0.5
                instance_exceptions.append(
                    ClassInstanceExceptionCreate(
                        exception_id=uuid.uuid4(),
                        class_id=class_id,
                        gym_id=gym_id,
                        original_date=exc_date,
                        is_cancelled=cancelled,
                        new_class_time=(
                            time(random.randint(6, 20), random.choice([0, 30]))
                            if not cancelled
                            else None
                        ),
                        new_instructor_id=(
                            random.choice(trainer_ids)
                            if not cancelled and trainer_ids and random.random() < 0.5
                            else None
                        ),
                    )
                )

        # ~15% of classes get a range exception (vacation week / sub instructor)
        if random.random() < 0.15:
            range_start = start_date + timedelta(days=random.randint(20, 90))
            range_end = range_start + timedelta(days=random.randint(3, 14))
            cancelled = random.random() < 0.5
            range_exceptions.append(
                ClassRangeExceptionCreate(
                    exception_id=uuid.uuid4(),
                    class_id=class_id,
                    gym_id=gym_id,
                    start_date=range_start,
                    end_date=range_end,
                    is_cancelled=cancelled,
                    new_instructor_id=(
                        random.choice(trainer_ids) if not cancelled and trainer_ids else None
                    ),
                )
            )

    return classes, instance_exceptions, range_exceptions


def _instructor_for_day(cls: GymClassCreate, day_short: str) -> uuid.UUID | None:
    return getattr(cls, f"{day_short}_instructor_id", None)


def _enumerate_occurrences(
    cls: GymClassCreate, until: date, max_count: int
) -> list[datetime]:
    """Walk the class's recurrence rule from start_date forward, returning
    up to `max_count` past occurrence datetimes (capped at `until`).
    """
    out: list[datetime] = []
    cursor = cls.start_date
    end = cls.end_date or until
    while cursor <= end and cursor <= until and len(out) < max_count:
        if cls.recurring_unit == RecurringUnit.daily:
            should_emit = True
        elif cls.recurring_unit == RecurringUnit.weekly:
            day_short = DAYS[(cursor.weekday() + 1) % 7]  # Mon=0 -> "mon", Sun=6 -> "sun"
            should_emit = getattr(cls, day_short)
        else:  # monthly
            should_emit = cursor.day == cls.start_date.day
        if should_emit:
            out.append(datetime.combine(cursor, cls.class_time))
        cursor += timedelta(days=1)
    return out


class _Coverage(NamedTuple):
    """A membership's coverage window for attendance attribution."""

    start: date
    end: date
    plan_id: UUID
    item_id: UUID
    is_live: bool


def _coverage_windows(
    membership_rows: list[MemberMembershipCreate],
    today: date,
) -> dict[UUID, list[_Coverage]]:
    """Build each member's membership coverage windows for attribution."""
    by_member: dict[UUID, list[_Coverage]] = defaultdict(list)
    for m in membership_rows:
        is_live = m.end_date is None and m.cancel_date is None
        end_window = m.end_date or m.cancel_date or today
        by_member[m.member_id].append(
            _Coverage(
                start=m.start_date,
                end=end_window,
                plan_id=m.plan_id,
                item_id=m.item_id,
                is_live=is_live,
            )
        )
    return by_member


def _find_cover(covers: list[_Coverage], when: date) -> _Coverage | None:
    """Pick the membership covering a date: prefer live, then earliest start."""
    matches = [c for c in covers if c.start <= when <= c.end]
    if not matches:
        return None
    return min(matches, key=lambda c: (not c.is_live, c.start))


def generate_class_history_and_attendance(
    gym_id: uuid.UUID,
    classes: list[GymClassCreate],
    members: list[MemberCreate],
    membership_rows: list[MemberMembershipCreate],
    instances_per_class: int = 30,
) -> tuple[list[ClassHistoryCreate], list[MemberAttendanceCreate]]:
    """Walk each class's schedule to produce class_history rows for past
    occurrences, then assign each member a random subset of the occurrences
    that fall within one of their membership windows as member_attendance.

    Attendance is hard-gated like the live check-in: a member with no
    membership covering an occurrence gets no attendance row, and every row
    is attributed to the covering membership's plan_id + item_id.
    """
    today = date.today()
    history: list[ClassHistoryCreate] = []
    attendance: list[MemberAttendanceCreate] = []

    for cls in classes:
        if not cls.is_active and random.random() < 0.5:
            # Skip half of inactive classes — they shouldn't all have heavy history
            continue

        occurrences = _enumerate_occurrences(cls, today, instances_per_class)
        for occ in occurrences:
            day_short = DAYS[(occ.date().weekday() + 1) % 7]
            instructor_id = _instructor_for_day(cls, day_short)
            history.append(
                ClassHistoryCreate(
                    class_history_id=uuid.uuid4(),
                    class_id=cls.class_id,
                    gym_id=gym_id,
                    instructor_id=instructor_id,
                    occurred_at=occ,
                    duration_minutes=cls.duration_minutes,
                )
            )

    if not history:
        return history, attendance

    windows_by_member = _coverage_windows(membership_rows, today)

    # Each member attends a random subset of the class_history rows that fall
    # within one of their membership windows (no membership -> no attendance).
    for member in members:
        covers = windows_by_member.get(member.member_id)
        if not covers:
            continue

        eligible = [
            (h, cover)
            for h in history
            if (cover := _find_cover(covers, h.occurred_at.date())) is not None
        ]
        if not eligible:
            continue
        if random.random() < 0.05:
            continue  # ~5% of covered members still never attended

        n_attended = random.randint(1, min(15, len(eligible)))
        for h, cover in random.sample(eligible, n_attended):
            attendance.append(
                MemberAttendanceCreate(
                    log_id=uuid.uuid4(),
                    member_id=member.member_id,
                    gym_id=gym_id,
                    class_history_id=h.class_history_id,
                    plan_id=cover.plan_id,
                    item_id=cover.item_id,
                )
            )

    return history, attendance
