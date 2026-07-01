"""Generators for gym_classes (identity), gym_class_schedules (append-only
schedule versions), exceptions, member_attendance, and class_signups."""

from __future__ import annotations

import calendar
import random
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from typing import NamedTuple
from uuid import UUID
from zoneinfo import ZoneInfo

from dateutil.relativedelta import relativedelta

from schema.gym_class import (
    ClassInstanceExceptionCreate,
    ClassRangeExceptionCreate,
    ClassSignupCreate,
    GymClassCreate,
    GymClassScheduleCreate,
    MemberAttendanceCreate,
    RecurringUnit,
)
from schema.gym_employee import GymEmployeeCreate
from schema.member import MemberCreate
from schema.member_membership import MemberMembershipCreate

# How far ahead of today a class's future occurrences get seeded sign-ups.
FUTURE_SIGNUP_HORIZON_DAYS = 7

# Chance a class shows a historical schedule change: two append-only
# gym_class_schedules versions instead of one, exercising versioned-past
# rendering (a class time or weekday-set change partway through its life).
VERSIONED_PAST_CHANCE = 0.3
# How recently (in weeks, inclusive range) the second version took effect,
# when a class gets one.
VERSION_RECENT_EFFECTIVE_FROM_WEEKS = (1, 6)

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
    gym_timezone: str,
    count: int,
    employees: list[GymEmployeeCreate],
) -> tuple[
    list[GymClassCreate],
    list[GymClassScheduleCreate],
    list[ClassInstanceExceptionCreate],
    list[ClassRangeExceptionCreate],
]:
    """Build classes (identity) + their schedule version(s) plus a few
    exceptions per gym.

    ~VERSIONED_PAST_CHANCE of classes get TWO schedule versions (a prior
    shape with a different class_time or weekday set, then the current
    shape taking over 1-6 weeks ago); the rest get one version effective
    from around when the class's recurrence started. Both versions of a
    class always freeze the same `gym_timezone` and share the same
    recurrence `start_date` -- only the shape (and when it took effect)
    differs.
    """
    templates = random.sample(CLASS_TEMPLATES, min(count, len(CLASS_TEMPLATES)))
    trainer_ids = [e.employee_id for e in employees]
    today = date.today()

    classes: list[GymClassCreate] = []
    schedules: list[GymClassScheduleCreate] = []
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
        start_date = today - timedelta(days=random.randint(60, 200))
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
            )
        )

        current_shape = {
            "class_time": time(hour, minute),
            "duration_minutes": tmpl["duration_minutes"],
            "recurring_unit": recurring_unit,
            "recurring_interval": 1,
            "start_date": start_date,
            "end_date": None,
            **day_flags,
            **instructor_kwargs,
        }
        class_versions = _build_schedule_versions(
            class_id, gym_id, gym_timezone, current_shape, start_date
        )
        schedules.extend(class_versions)

        # ~30% of classes get 1-2 single-instance exceptions, targeting a
        # real owned occurrence date (whichever version owns it) so the
        # exception is never inert.
        if random.random() < 0.3:
            window_end = today + timedelta(days=FUTURE_SIGNUP_HORIZON_DAYS)
            owned_dates = [
                d
                for d in _owned_candidate_dates(class_versions, window_end)
                if d <= start_date + timedelta(days=60)
            ]
            used_dates: set[date] = set()
            for _ in range(random.randint(1, 2)):
                available = [d for d in owned_dates if d not in used_dates]
                if not available:
                    break
                exc_date = random.choice(available)
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

    return classes, schedules, instance_exceptions, range_exceptions


def select_attendance_eligible_classes(
    classes: list[GymClassCreate],
) -> list[GymClassCreate]:
    """Classes eligible for past attendance/sign-up seeding.

    Skips half of the inactive classes (drawn once, here) so they don't all
    carry heavy history -- both `generate_attendance` and
    `generate_class_signups` take this SAME filtered list so a class's
    "skipped" decision is made exactly once and shared, keeping past
    sign-ups scoped to the same occurrences that could have attendance.
    """
    return [cls for cls in classes if cls.is_active or random.random() >= 0.5]


# -- Schedule versioning ---------------------------------------------------


def _build_schedule_versions(
    class_id: uuid.UUID,
    gym_id: uuid.UUID,
    gym_timezone: str,
    current_shape: dict,
    start_date: date,
) -> list[GymClassScheduleCreate]:
    """One (~70%) or two (~30%) append-only schedule versions for a class.

    A single-version class's one version is effective from a past instant
    around when its recurrence started (the FIRST version of a class owns
    occurrences back to negative infinity regardless -- see
    ClassesVersionExpander -- but a plausible value keeps the seeded row
    honest). A two-version class exercises the versioned past: v1 (a
    different class_time or weekday set, everything else identical) is
    effective from that same early instant; v2 (the class's "current" shape,
    `current_shape`) takes over 1-6 weeks ago. Both freeze `gym_timezone`
    and share `start_date` (the recurrence anchor never moves -- only the
    shape, and when it took effect, differs). effective_from values are
    timezone-aware UTC datetimes, strictly increasing per class.
    """
    early_effective_from = datetime.combine(
        start_date, time(0, 0), tzinfo=timezone.utc
    )
    if random.random() >= VERSIONED_PAST_CHANCE:
        return [
            GymClassScheduleCreate(
                schedule_id=uuid.uuid4(),
                class_id=class_id,
                gym_id=gym_id,
                effective_from=early_effective_from,
                timezone=gym_timezone,
                **current_shape,
            )
        ]

    earlier_shape = _vary_shape(current_shape)
    min_weeks, max_weeks = VERSION_RECENT_EFFECTIVE_FROM_WEEKS
    recent_effective_from = datetime.now(timezone.utc) - timedelta(
        weeks=random.uniform(min_weeks, max_weeks)
    )
    return [
        GymClassScheduleCreate(
            schedule_id=uuid.uuid4(),
            class_id=class_id,
            gym_id=gym_id,
            effective_from=early_effective_from,
            timezone=gym_timezone,
            **earlier_shape,
        ),
        GymClassScheduleCreate(
            schedule_id=uuid.uuid4(),
            class_id=class_id,
            gym_id=gym_id,
            effective_from=recent_effective_from,
            timezone=gym_timezone,
            **current_shape,
        ),
    ]


def _vary_shape(shape: dict) -> dict:
    """A prior version's shape: the current shape with EITHER its
    class_time OR (weekly only) its weekday set changed, everything else
    (duration, instructors, recurrence range) identical -- a real historical
    schedule change without needing an independently-generated instructor
    lineup.
    """
    varied = dict(shape)
    if varied["recurring_unit"] == RecurringUnit.weekly and random.random() < 0.5:
        # Flip one weekday's flag: guarantees a different active-day set.
        day_to_flip = random.choice(DAYS)
        varied[day_to_flip] = not varied[day_to_flip]
        if not any(varied[d] for d in DAYS):
            # A weekly class must keep >=1 active day (the live CHECK /
            # ClassesCrudService._validate_weekly) -- flipping the only
            # active day off would violate it, so flip a second day on.
            other_day = random.choice([d for d in DAYS if d != day_to_flip])
            varied[other_day] = True
    else:
        old_time: time = varied["class_time"]
        offset = random.choice([-3, -2, -1, 1, 2, 3])
        varied["class_time"] = time((old_time.hour + offset) % 24, old_time.minute)
    return varied


# -- Pure recurrence enumeration (mirrors ClassesExpander) -----------------


def _instructor_for_day(
    schedule: GymClassScheduleCreate, day_short: str
) -> uuid.UUID | None:
    return getattr(schedule, f"{day_short}_instructor_id", None)


def _weekday_short(d: date) -> str:
    """Map a date to its DAYS short name (Mon=0..Sun=6 -> "mon".."sun")."""
    return DAYS[(d.weekday() + 1) % 7]


def _enumerate_occurrences(
    schedule: GymClassScheduleCreate, until: date, max_count: int
) -> list[date]:
    """Enumerate one schedule version's recurrence rule from its start_date
    forward, honoring recurring_interval, returning up to `max_count`
    occurrence DATES no later than `until` (or the version's end_date).
    Time-of-day and any exception overrides are applied later, when each
    occurrence is resolved.
    """
    interval = schedule.recurring_interval
    end = min(schedule.end_date or until, until)
    out: list[date] = []

    if schedule.recurring_unit == RecurringUnit.monthly:
        # Anchor each month off start_date (never chained), clamping the day to
        # the month's length so Jan 31 -> Feb 28/29 -> Mar 31 stays correct.
        n = 0
        while len(out) < max_count:
            anchor = schedule.start_date + relativedelta(months=n * interval)
            last_day = calendar.monthrange(anchor.year, anchor.month)[1]
            occ = anchor.replace(day=min(schedule.start_date.day, last_day))
            if occ > end:
                break
            out.append(occ)
            n += 1
        return out

    cursor = schedule.start_date
    while cursor <= end and len(out) < max_count:
        days_from_start = (cursor - schedule.start_date).days
        if schedule.recurring_unit == RecurringUnit.daily:
            should_emit = days_from_start % interval == 0
        else:  # weekly
            week_index = days_from_start // 7
            should_emit = bool(
                week_index % interval == 0 and getattr(schedule, _weekday_short(cursor))
            )
        if should_emit:
            out.append(cursor)
        cursor += timedelta(days=1)
    return out


class _OccurrenceSnapshot(NamedTuple):
    """One resolved occurrence: identity (original slot, pre-exception) plus
    its effective render (post-exception)."""

    original_date: date
    original_time: time
    emit_date: date
    class_time: time
    duration_minutes: int
    instructor_id: UUID | None


def _instance_exceptions_by_class(
    exceptions: list[ClassInstanceExceptionCreate],
) -> dict[UUID, dict[date, ClassInstanceExceptionCreate]]:
    """Index instance exceptions by class_id, then by original_date (unique)."""
    by_class: dict[UUID, dict[date, ClassInstanceExceptionCreate]] = defaultdict(dict)
    for exc in exceptions:
        by_class[exc.class_id][exc.original_date] = exc
    return by_class


def _range_exceptions_by_class(
    exceptions: list[ClassRangeExceptionCreate],
) -> dict[UUID, list[ClassRangeExceptionCreate]]:
    """Index range exceptions by class_id, preserving creation order so the
    earliest-created covering range wins when ranges overlap.
    """
    by_class: dict[UUID, list[ClassRangeExceptionCreate]] = defaultdict(list)
    for exc in exceptions:
        by_class[exc.class_id].append(exc)
    return by_class


def _schedules_by_class(
    schedules: list[GymClassScheduleCreate],
) -> dict[UUID, list[GymClassScheduleCreate]]:
    """Index schedule versions by class_id."""
    by_class: dict[UUID, list[GymClassScheduleCreate]] = defaultdict(list)
    for s in schedules:
        by_class[s.class_id].append(s)
    return dict(by_class)


def _covering_range(
    ranges: list[ClassRangeExceptionCreate], when: date
) -> ClassRangeExceptionCreate | None:
    """The earliest-created range exception covering `when` (inclusive)."""
    for exc in ranges:
        if exc.start_date <= when <= exc.end_date:
            return exc
    return None


def _resolve_occurrence(
    schedule: GymClassScheduleCreate,
    original_date: date,
    instance_exceptions: dict[date, ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
) -> _OccurrenceSnapshot | None:
    """Resolve one candidate date under `schedule`'s shape against the
    class's seeded exceptions. Returns None ONLY when cancelled (an instance
    exception's cancel, or a covering range exception's cancel) -- mirrors
    ClassesExpander._resolve with include_cancelled=False: a cancelled date
    never "claims" the date for cross-version dedup purposes. A reschedule
    keeps `original_date` as the identity and moves `emit_date`; the caller
    decides past-vs-future by `emit_date`, not `original_date`.
    """
    default_instructor = _instructor_for_day(schedule, _weekday_short(original_date))

    instance = instance_exceptions.get(original_date)
    if instance is not None:
        if instance.is_cancelled:
            return None
        emit_date = instance.new_date if instance.new_date is not None else original_date
        return _OccurrenceSnapshot(
            original_date=original_date,
            original_time=schedule.class_time,
            emit_date=emit_date,
            class_time=(
                instance.new_class_time
                if instance.new_class_time is not None
                else schedule.class_time
            ),
            duration_minutes=(
                instance.new_duration_minutes
                if instance.new_duration_minutes is not None
                else schedule.duration_minutes
            ),
            instructor_id=(
                instance.new_instructor_id
                if instance.new_instructor_id is not None
                else default_instructor
            ),
        )

    covering = _covering_range(range_exceptions, original_date)
    if covering is not None:
        if covering.is_cancelled:
            return None
        return _OccurrenceSnapshot(
            original_date=original_date,
            original_time=schedule.class_time,
            emit_date=original_date,
            class_time=schedule.class_time,
            duration_minutes=schedule.duration_minutes,
            instructor_id=(
                covering.new_instructor_id
                if covering.new_instructor_id is not None
                else default_instructor
            ),
        )

    return _OccurrenceSnapshot(
        original_date=original_date,
        original_time=schedule.class_time,
        emit_date=original_date,
        class_time=schedule.class_time,
        duration_minutes=schedule.duration_minutes,
        instructor_id=default_instructor,
    )


# -- Version ownership (mirrors ClassesVersionExpander) --------------------


def _original_start_at(schedule: GymClassScheduleCreate, when: date) -> datetime:
    """UTC instant of `when`'s slot under `schedule` -- mirrors
    ClassesVersionExpander.original_start_at (the version's OWN frozen tz)."""
    return datetime.combine(
        when, schedule.class_time, tzinfo=ZoneInfo(schedule.timezone)
    ).astimezone(timezone.utc)


def _owned_candidate_dates(
    versions: list[GymClassScheduleCreate], window_end: date
) -> list[date]:
    """Raw per-version recurrence candidates, owned + deduped -- no
    exceptions applied. Used to pick real occurrence dates for seeded
    exceptions before any exceptions exist. Mirrors the ownership-window +
    no-day-doubling rules of ClassesVersionExpander, minus exception
    resolution.
    """
    ordered = sorted(versions, key=lambda v: v.effective_from)
    claimed: set[date] = set()
    dates: list[date] = []
    for i, version in enumerate(ordered):
        window_from = ordered[i].effective_from if i > 0 else None
        window_until = ordered[i + 1].effective_from if i + 1 < len(ordered) else None
        for original_date in _enumerate_occurrences(version, window_end, max_count=10_000):
            if original_date in claimed:
                continue
            slot_instant = _original_start_at(version, original_date)
            if window_from is not None and slot_instant < window_from:
                continue
            if window_until is not None and slot_instant >= window_until:
                continue
            claimed.add(original_date)
            dates.append(original_date)
    dates.sort()
    return dates


def _owned_occurrences(
    versions: list[GymClassScheduleCreate],
    instance_exceptions: dict[date, ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
    window_end: date,
) -> list[_OccurrenceSnapshot]:
    """All of a class's resolved occurrences across its schedule versions,
    honoring ownership windows + earliest-version-wins dedup -- mirrors
    ClassesVersionExpander.expand(). Bounded above by `window_end`
    (today + the future sign-up horizon); each version's own `start_date`
    bounds it below. A cancelled candidate never claims its date (matching
    the live expander's include_cancelled=False semantics), so a different
    version may claim the same date instead.
    """
    ordered = sorted(versions, key=lambda v: v.effective_from)
    claimed: set[date] = set()
    resolved: list[_OccurrenceSnapshot] = []
    for i, version in enumerate(ordered):
        window_from = ordered[i].effective_from if i > 0 else None
        window_until = ordered[i + 1].effective_from if i + 1 < len(ordered) else None
        for original_date in _enumerate_occurrences(version, window_end, max_count=10_000):
            if original_date in claimed:
                continue
            slot_instant = _original_start_at(version, original_date)
            if window_from is not None and slot_instant < window_from:
                continue
            if window_until is not None and slot_instant >= window_until:
                continue
            snapshot = _resolve_occurrence(
                version, original_date, instance_exceptions, range_exceptions
            )
            if snapshot is None:
                continue  # cancelled -- doesn't claim the date
            claimed.add(original_date)
            resolved.append(snapshot)
    resolved.sort(key=lambda s: s.original_date)
    return resolved


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


def generate_attendance(
    gym_id: uuid.UUID,
    gym_timezone: str,
    eligible_classes: list[GymClassCreate],
    schedules: list[GymClassScheduleCreate],
    members: list[MemberCreate],
    membership_rows: list[MemberMembershipCreate],
    instance_exceptions: list[ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
    instances_per_class: int = 30,
) -> list[MemberAttendanceCreate]:
    """Walk each eligible class's schedule version(s) to produce
    member_attendance rows for past occurrences -- resolved against the
    class's version ownership + seeded exceptions (`_owned_occurrences`) so
    attendance matches the real schedule -- then assign each member a random
    subset of the occurrences that fall within one of their membership
    windows.

    Attendance is hard-gated like the live check-in: a member with no
    membership covering an occurrence gets no attendance row, and every row
    is attributed to the covering membership's plan_id + item_id, keyed by
    the occurrence's ORIGINAL slot (original_date + the owning version's
    original_time) with `occurred_at` as the denormalized effective UTC
    instant.
    """
    today = date.today()
    window_end = today + timedelta(days=FUTURE_SIGNUP_HORIZON_DAYS)
    schedules_by_class = _schedules_by_class(schedules)
    instances_by_class = _instance_exceptions_by_class(instance_exceptions)
    ranges_by_class = _range_exceptions_by_class(range_exceptions)

    # Per-class capped (earliest-first) pool of past attendance-eligible
    # occurrences -- see docs/seed.mermaid's "<=N occurrences" cap.
    past_by_class: dict[UUID, list[_OccurrenceSnapshot]] = {}
    for cls in eligible_classes:
        versions = schedules_by_class.get(cls.class_id)
        if not versions:
            continue
        occurrences = _owned_occurrences(
            versions,
            instances_by_class.get(cls.class_id, {}),
            ranges_by_class.get(cls.class_id, []),
            window_end,
        )
        past = [o for o in occurrences if o.emit_date <= today][:instances_per_class]
        if past:
            past_by_class[cls.class_id] = past

    attendance: list[MemberAttendanceCreate] = []
    if not past_by_class:
        return attendance

    windows_by_member = _coverage_windows(membership_rows, today)

    # Each member attends a random subset of the occurrences that fall
    # within one of their membership windows (no membership -> no attendance).
    for member in members:
        covers = windows_by_member.get(member.member_id)
        if not covers:
            continue

        eligible: list[tuple[UUID, _OccurrenceSnapshot, _Coverage]] = [
            (class_id, occ, cover)
            for class_id, occs in past_by_class.items()
            for occ in occs
            if (cover := _find_cover(covers, occ.emit_date)) is not None
        ]
        if not eligible:
            continue
        if random.random() < 0.05:
            continue  # ~5% of covered members still never attended

        n_attended = random.randint(1, min(15, len(eligible)))
        for class_id, occ, cover in random.sample(eligible, n_attended):
            attendance.append(
                MemberAttendanceCreate(
                    log_id=uuid.uuid4(),
                    member_id=member.member_id,
                    gym_id=gym_id,
                    class_id=class_id,
                    original_date=occ.original_date,
                    original_time=occ.original_time,
                    # Interpret the effective wall-clock time in the gym's
                    # timezone, then convert to UTC -- identical to
                    # ClassesExpander, so the runtime resolver's occurred_at
                    # matches the seeded row instead of diverging from it.
                    occurred_at=datetime.combine(
                        occ.emit_date,
                        occ.class_time,
                        tzinfo=ZoneInfo(gym_timezone),
                    ).astimezone(timezone.utc),
                    plan_id=cover.plan_id,
                    item_id=cover.item_id,
                )
            )

    return attendance


def _effective_capacity(
    cls: GymClassCreate,
    instances_by_class: dict[UUID, dict[date, ClassInstanceExceptionCreate]],
    original_date: date,
) -> int | None:
    """The class's max_capacity, overridden per-occurrence by an instance
    exception's new_max_capacity when one is set for that ORIGINAL date
    (instance exceptions are keyed by original_date, not the effective/
    post-reschedule date). None means unlimited -- never blocks. Mirrors
    SignupService._effective_capacity's resolution (class default, exception
    override wins) on the live path.
    """
    exc = instances_by_class.get(cls.class_id, {}).get(original_date)
    if exc is not None and exc.new_max_capacity is not None:
        return exc.new_max_capacity
    return cls.max_capacity


def _past_signups_for_occurrence(
    gym_id: uuid.UUID,
    cls: GymClassCreate,
    occ: _OccurrenceSnapshot,
    attended_ids: list[UUID],
    instances_by_class: dict[UUID, dict[date, ClassInstanceExceptionCreate]],
    member_ids: list[UUID],
) -> list[ClassSignupCreate]:
    """Sign-ups for one already-occurred occurrence: a realistic mix of
    signed-up-and-attended, no-show (signed up, never attended), and walk-in
    (attended, no sign-up row -- left alone, so attendance is untouched).

    Respects `max_capacity` by never growing the signed-up-or-attended count
    past it: no-show sign-ups only fill whatever room remains after the
    occurrence's (already-generated, unbounded) attendance count -- when
    attendance alone already fills/exceeds the room, only already-attended
    members get a mirrored sign-up row.
    """
    if not attended_ids and random.random() < 0.7:
        return []  # most attendance-less occurrences stay signup-less too

    effective_capacity = _effective_capacity(
        cls, instances_by_class, occ.original_date
    )

    # Some attended members also get a mirrored sign-up row
    # (signed-up-and-attended); the rest stay walk-ins.
    signed_and_attended = {m for m in attended_ids if random.random() < 0.65}

    # No-shows: signed up, never attended -- capped by whatever room is
    # left under the effective capacity after the attended count.
    room = (
        3
        if effective_capacity is None
        else max(effective_capacity - len(attended_ids), 0)
    )
    attended_set = set(attended_ids)
    no_show_pool = [m for m in member_ids if m not in attended_set]
    no_shows: set[UUID] = set()
    max_no_shows = min(len(no_show_pool), 3, room)
    if max_no_shows > 0 and random.random() < 0.5:
        no_shows = set(random.sample(no_show_pool, random.randint(1, max_no_shows)))

    return [
        ClassSignupCreate(
            signup_id=uuid.uuid4(),
            gym_id=gym_id,
            class_id=cls.class_id,
            member_id=member_id,
            original_date=occ.original_date,
            original_time=occ.original_time,
        )
        for member_id in signed_and_attended | no_shows
    ]


def _future_signups_for_occurrence(
    gym_id: uuid.UUID,
    cls: GymClassCreate,
    occ: _OccurrenceSnapshot,
    instances_by_class: dict[UUID, dict[date, ClassInstanceExceptionCreate]],
    member_ids: list[UUID],
) -> list[ClassSignupCreate]:
    """Sign-ups-only for a not-yet-occurred occurrence -- no attendance
    exists yet. Respects the occurrence's effective max_capacity as the draw
    pool's cap.
    """
    if not member_ids:
        return []
    effective_capacity = _effective_capacity(
        cls, instances_by_class, occ.original_date
    )
    pool_size = (
        min(len(member_ids), 8)
        if effective_capacity is None
        else min(effective_capacity, len(member_ids))
    )
    if pool_size == 0:
        return []
    k = random.randint(0, pool_size)
    if k == 0:
        return []
    return [
        ClassSignupCreate(
            signup_id=uuid.uuid4(),
            gym_id=gym_id,
            class_id=cls.class_id,
            member_id=member_id,
            original_date=occ.original_date,
            original_time=occ.original_time,
        )
        for member_id in random.sample(member_ids, k)
    ]


def generate_class_signups(
    gym_id: uuid.UUID,
    gym_timezone: str,
    classes: list[GymClassCreate],
    eligible_classes: list[GymClassCreate],
    schedules: list[GymClassScheduleCreate],
    members: list[MemberCreate],
    attendance: list[MemberAttendanceCreate],
    instance_exceptions: list[ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
    instances_per_class: int = 30,
) -> list[ClassSignupCreate]:
    """Seed class_signups (reservations, NOT attendance) for both past and
    future occurrences, so old classes show a realistic "N signed up / M
    attended" mix and upcoming classes show "N signed up".

    Past sign-ups are scoped to the SAME per-class occurrence pool
    `generate_attendance` used (`eligible_classes` + the same
    `instances_per_class` cap), keyed by each occurrence's ORIGINAL slot so
    they line up with the already-generated `attendance` rows. Future
    sign-ups are freshly enumerated up to FUTURE_SIGNUP_HORIZON_DAYS ahead
    for active, non-deleted classes only -- `member_attendance` is never
    written for a future occurrence; a sign-up is a reservation, not
    attendance, so the future side of this function is the only seeding a
    not-yet-occurred class gets.
    """
    if not members or not classes:
        return []

    today = date.today()
    window_end = today + timedelta(days=FUTURE_SIGNUP_HORIZON_DAYS)
    schedules_by_class = _schedules_by_class(schedules)
    instances_by_class = _instance_exceptions_by_class(instance_exceptions)
    ranges_by_class = _range_exceptions_by_class(range_exceptions)
    member_ids = [m.member_id for m in members]
    eligible_ids = {cls.class_id for cls in eligible_classes}

    attendance_by_occurrence: dict[tuple[UUID, date], list[UUID]] = defaultdict(list)
    for a in attendance:
        attendance_by_occurrence[(a.class_id, a.original_date)].append(a.member_id)

    signups: list[ClassSignupCreate] = []
    for cls in classes:
        versions = schedules_by_class.get(cls.class_id)
        if not versions:
            continue
        occurrences = _owned_occurrences(
            versions,
            instances_by_class.get(cls.class_id, {}),
            ranges_by_class.get(cls.class_id, []),
            window_end,
        )

        if cls.class_id in eligible_ids:
            past = [o for o in occurrences if o.emit_date <= today][:instances_per_class]
            for occ in past:
                attended_ids = attendance_by_occurrence.get(
                    (cls.class_id, occ.original_date), []
                )
                signups.extend(
                    _past_signups_for_occurrence(
                        gym_id, cls, occ, attended_ids, instances_by_class, member_ids
                    )
                )

        if cls.is_active and not cls.is_deleted:  # mirrors SignupService's validation
            future = [o for o in occurrences if o.emit_date > today]
            for occ in future:
                signups.extend(
                    _future_signups_for_occurrence(
                        gym_id, cls, occ, instances_by_class, member_ids
                    )
                )

    return signups
