import random
import uuid
from datetime import time, timedelta

from schema.gym_class import (
    GymClassCreate,
    GymClassExceptionCreate,
    GymClassLogCreate,
    GymClassScheduleCreate,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member_membership import MemberMembershipCreate
from schema.membership_plan import MembershipPlanCreate
from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_date, random_past_datetime

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

def _is_short_term_only(allowed_plans: list | None) -> bool:
    """True when every allowed plan is trial or one_time (no recurring)."""
    if not allowed_plans:
        return False
    return all(p.plan_type in ("trial", "one_time") for p in allowed_plans)


def generate(
    gym_id: uuid.UUID,
    count: int,
    employees: list[GymEmployeeCreate],
    plans: list[MembershipPlanCreate],
) -> tuple[
    list[GymClassCreate],
    list[GymClassScheduleCreate],
    list[GymClassExceptionCreate],
]:
    templates = random.sample(CLASS_TEMPLATES, min(count, len(CLASS_TEMPLATES)))
    trainer_ids = [e.employee_id for e in employees]
    plan_ids = [p.plan_id for p in plans]
    plan_by_id = {p.plan_id: p for p in plans}

    parents: list[GymClassCreate] = []
    schedules: list[GymClassScheduleCreate] = []
    exceptions: list[GymClassExceptionCreate] = []

    for tmpl in templates:
        class_id = uuid.uuid4()

        # Random class time between 6am and 8pm
        hour = random.randint(6, 20)
        minute = random.choice([0, 15, 30, 45])

        # Pick recurring unit
        recurring_unit = random.choices(
            ["weekly", "daily", "monthly"], weights=[80, 10, 10]
        )[0]

        day_flags = {d: False for d in DAYS}
        if recurring_unit == "daily":
            day_flags = {d: True for d in DAYS}
        elif recurring_unit == "weekly":
            num_days = random.randint(2, 5)
            for d in random.sample(DAYS, num_days):
                day_flags[d] = True

        # Assign instructors to active days (80% chance per day)
        instructor_ids = {}
        for d in DAYS:
            if day_flags[d] and trainer_ids and random.random() < 0.8:
                instructor_ids[f"{d}_instructor_id"] = random.choice(trainer_ids)

        # 30% of classes restrict to specific plans
        allowed_plan_ids = None
        if plan_ids and random.random() < 0.3:
            num_plans = random.randint(1, min(3, len(plan_ids)))
            allowed_plan_ids = random.sample(plan_ids, num_plans)

        # Max capacity: 70% have one
        max_capacity = None
        if random.random() < 0.7:
            max_capacity = random.choice([10, 15, 20, 25, 30])

        allowed_plans = (
            [plan_by_id[pid] for pid in allowed_plan_ids]
            if allowed_plan_ids
            else None
        )
        short_term = _is_short_term_only(allowed_plans)

        # Schedule start goes back 200 days to cover membership window (180 days).
        # end_date is always None (DB trigger forbids gaps for a single segment).
        # Short-term classes are marked inactive instead.
        start_date = random_past_date(200)
        end_date = None

        # Short-term-only classes are always inactive (class ran and ended).
        # Others: 20% inactive.
        is_active = False if short_term else random.random() < 0.8

        # Parent record
        parents.append(GymClassCreate(
            class_id=class_id,
            gym_id=gym_id,
            class_name=tmpl["class_name"],
            class_description=tmpl["class_description"],
            allowed_plan_ids=allowed_plan_ids,
            max_capacity=max_capacity,
            is_active=is_active,
        ))

        schedule_id = uuid.uuid4()
        schedules.append(
            GymClassScheduleCreate(
                schedule_id=schedule_id,
                class_id=class_id,
                gym_id=gym_id,
                class_time=time(hour, minute),
                duration_minutes=tmpl["duration_minutes"],
                recurring_unit=recurring_unit,
                recurring_interval=1,
                start_date=start_date,
                end_date=end_date,
                **day_flags,
                **instructor_ids,
            )
        )

        # 30% of schedules get 1-2 exceptions
        if random.random() < 0.3:
            num_exceptions = random.randint(1, 2)
            used_dates: set = set()
            for _ in range(num_exceptions):
                # Random date within the schedule's range
                days_offset = random.randint(0, 30)
                exc_date = start_date + timedelta(days=days_offset)
                if exc_date in used_dates:
                    continue
                used_dates.add(exc_date)

                is_cancelled = random.random() < 0.5
                exceptions.append(
                    GymClassExceptionCreate(
                        exception_id=uuid.uuid4(),
                        schedule_id=schedule_id,
                        gym_id=gym_id,
                        original_date=exc_date,
                        is_cancelled=is_cancelled if is_cancelled else None,
                        new_class_time=(
                            time(random.randint(6, 20), random.choice([0, 30]))
                            if not is_cancelled
                            else None
                        ),
                        new_instructor_id=(
                            random.choice(trainer_ids)
                            if not is_cancelled and trainer_ids and random.random() < 0.5
                            else None
                        ),
                    )
                )

    return parents, schedules, exceptions


def generate_logs(
    gym_id: uuid.UUID,
    schedules: list[GymClassScheduleCreate],
    profiles: list[UserGymProfileCreate],
    memberships: list[MemberMembershipCreate],
) -> list[GymClassLogCreate]:
    from datetime import date, datetime

    logs: list[GymClassLogCreate] = []
    if not schedules:
        return logs

    today = date.today()

    # Index memberships by crm_user_id for quick lookup
    memberships_by_user: dict[uuid.UUID, list[MemberMembershipCreate]] = {}
    for m in memberships:
        memberships_by_user.setdefault(m.crm_user_id, []).append(m)

    # Index profiles for parent freeze lookup (linked accounts inherit freeze)
    profile_by_id: dict[uuid.UUID, UserGymProfileCreate] = {p.crm_user_id: p for p in profiles}

    for profile in profiles:
        user_memberships = memberships_by_user.get(profile.crm_user_id)
        if not user_memberships:
            continue

        # Linked accounts inherit freeze from their parent
        if profile.account_linked_to_id and profile.account_linked_to_id in profile_by_id:
            freeze_profile = profile_by_id[profile.account_linked_to_id]
        else:
            freeze_profile = profile

        for membership in user_memberships:
            # Determine the active window for this membership
            window_start = membership.start_date
            window_end = min(
                membership.end_date or today,
                membership.cancel_date or today,
                today,
            )
            if window_end <= window_start:
                continue

            total_days = (window_end - window_start).days

            # Subtract frozen period if it overlaps the active window
            if freeze_profile.freeze_start_date and freeze_profile.freeze_end_date:
                freeze_start = max(freeze_profile.freeze_start_date, window_start)
                freeze_end = min(freeze_profile.freeze_end_date, window_end)
                if freeze_end > freeze_start:
                    total_days -= (freeze_end - freeze_start).days

            if total_days <= 0:
                continue

            # Scale attendance by weeks: random(1, 5) classes per week
            weeks = max(total_days / 7, 1)
            classes_per_week = random.randint(1, 5)
            num_logs = max(round(classes_per_week * weeks), 1)

            for _ in range(num_logs):
                # Pick a random day within the active window, avoiding frozen period
                for _attempt in range(10):
                    days_offset = random.randint(0, (window_end - window_start).days - 1)
                    log_date = window_start + timedelta(days=days_offset)
                    # Skip if inside frozen period
                    if (
                        freeze_profile.freeze_start_date
                        and freeze_profile.freeze_end_date
                        and freeze_profile.freeze_start_date <= log_date <= freeze_profile.freeze_end_date
                    ):
                        continue
                    break
                else:
                    continue

                # Random time of day (6am-9pm)
                log_time = datetime(
                    log_date.year, log_date.month, log_date.day,
                    random.randint(6, 21), random.randint(0, 59),
                )

                schedule = random.choice(schedules)

                # Pick a random instructor from the schedule's active days
                active_days = [d for d in DAYS if getattr(schedule, d)]
                instructor_id = None
                if active_days:
                    day = random.choice(active_days)
                    instructor_id = getattr(schedule, f"{day}_instructor_id", None)

                logs.append(
                    GymClassLogCreate(
                        log_id=uuid.uuid4(),
                        crm_user_id=profile.crm_user_id,
                        gym_id=gym_id,
                        class_id=schedule.class_id,
                        plan_id=membership.plan_id,
                        item_id=membership.item_id,
                        instructor_id=instructor_id,
                        time=log_time,
                    )
                )

    return logs
