"""Generators for gym_classes (identity), gym_class_schedules (append-only
schedule versions), exceptions, member_attendance, and class_signups.

This is the MIRROR of the runtime recurrence+exception engine
(FastApiBackend/src/classes/service/classes_expander.py, wrapped by
classes_version_expander.py) -- byte-for-byte in the recurrence, exception,
and version-ownership semantics, so seeded history and the live board can
never disagree. The one shape difference is deliberate: this module walks
GymClassScheduleCreate rows directly (a raw dict-shaped mirror of
ExpanderClass/ExpanderScheduleVersion) rather than importing the FastAPI
backend's Pydantic contracts, and stamps occurred_at as naive UTC (see
_original_start_at / generate_attendance) rather than doing a real
gym-timezone conversion the way the backend's ClassesExpander._build does.

weekday_slots (day -> ordered slot list; "all" for daily/monthly) is the
WHEN of a schedule shape, fanned out per-slot exactly like the runtime
expander's _slots_for / _resolve_date / _resolve_slot: a candidate date
carries every slot of its weekday key (weekly) or the "all" key
(daily/monthly), and each slot resolves independently against its OWN
instance exception, keyed (original_date, original_time) -- the occurrence's
permanent identity slot, exactly what member_attendance / class_signups /
class_instance_exceptions key.
"""

from __future__ import annotations

import calendar
import random
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from typing import NamedTuple
from uuid import UUID
from zoneinfo import ZoneInfo

from constants import MAX_CLASSES_ATTENDED_PER_MEMBER
from dateutil.relativedelta import relativedelta

from schema.gym_class import (
    ClassInstanceExceptionCreate,
    ClassRangeExceptionCreate,
    ClassSignupCreate,
    GymClassCreate,
    GymClassScheduleCreate,
    MemberAttendanceCreate,
    RecurringUnit,
    ScheduleSlot,
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

# The reserved weekday_slots key daily/monthly schedules use -- mirrors
# ClassesExpander's ALL_DAYS_KEY.
ALL_SLOTS_KEY = "all"
# Chance a class gets a genuine multi-time day: two distinct-time slots on
# the same weekday ("all" for daily/monthly) instead of just one, so seeded
# data exercises the multi-time-per-day feature (a meaningful minority, not
# the majority).
MULTI_SLOT_CLASS_CHANCE = 0.25
# The hour/minute pool a synthesized slot time is drawn from.
_SLOT_HOUR_RANGE = (6, 20)
_SLOT_MINUTES = (0, 15, 30, 45)

# Every template carries an image_url: gym_classes.image_url is NOT NULL and
# this seed inserts DIRECTLY into the table (no backend default-fill on this
# path). Photos come from the same human-curated Pexels pool the VideoService
# gym templates / CRM showcase use.
CLASS_TEMPLATES = [
    {"class_name": "Morning BJJ", "class_description": "Fundamentals and sparring for all levels.", "duration_minutes": 60, "image_url": "https://images.pexels.com/photos/8612009/pexels-photo-8612009.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Evening MMA", "class_description": "Mixed martial arts striking and grappling.", "duration_minutes": 90, "image_url": "https://images.pexels.com/photos/7991668/pexels-photo-7991668.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Kickboxing", "class_description": "High-energy kickboxing cardio and technique.", "duration_minutes": 60, "image_url": "https://images.pexels.com/photos/6296002/pexels-photo-6296002.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Open Mat", "class_description": "Free training time with open sparring.", "duration_minutes": 120, "image_url": "https://images.pexels.com/photos/29956727/pexels-photo-29956727.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Wrestling", "class_description": "Takedowns, control, and scrambles.", "duration_minutes": 60, "image_url": "https://images.pexels.com/photos/8612465/pexels-photo-8612465.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Muay Thai", "class_description": "Traditional Thai boxing with pads and bags.", "duration_minutes": 75, "image_url": "https://images.pexels.com/photos/4761788/pexels-photo-4761788.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "No-Gi Grappling", "class_description": "Submission grappling without the gi.", "duration_minutes": 60, "image_url": "https://images.pexels.com/photos/6765021/pexels-photo-6765021.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Kids Martial Arts", "class_description": "Fun and discipline-focused class for ages 6-12.", "duration_minutes": 45, "image_url": "https://images.pexels.com/photos/7045594/pexels-photo-7045594.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Competition Team", "class_description": "Advanced training for competitors.", "duration_minutes": 90, "image_url": "https://images.pexels.com/photos/7991616/pexels-photo-7991616.jpeg?auto=compress&cs=tinysrgb&w=1200"},
    {"class_name": "Strength & Conditioning", "class_description": "Athletic performance training.", "duration_minutes": 60, "image_url": "https://images.pexels.com/photos/4720230/pexels-photo-4720230.jpeg?auto=compress&cs=tinysrgb&w=1200"},
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
    weekday_slots shape -- a shifted slot time, an added/removed slot, or
    (weekly only) a different weekday set -- then the current shape taking
    over 1-6 weeks ago); the rest get one version effective from around when
    the class's recurrence started. Both versions of a class always freeze
    the same `gym_timezone` and share the same recurrence `start_date` --
    only the shape (and when it took effect) differs. A meaningful minority
    of classes (~MULTI_SLOT_CLASS_CHANCE) get a genuine multi-time day (two
    distinct-time slots on one weekday/"all" key) so seeded data exercises
    the multi-time-per-day feature.
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

        recurring_unit = random.choices(
            [RecurringUnit.weekly, RecurringUnit.daily, RecurringUnit.monthly],
            weights=[80, 10, 10],
        )[0]
        weekday_slots = _build_weekday_slots(recurring_unit, trainer_ids)

        max_capacity = random.choice([10, 15, 20, 25, 30]) if random.random() < 0.7 else None
        start_date = today - timedelta(days=random.randint(60, 200))
        is_active = random.random() < 0.85

        classes.append(
            GymClassCreate(
                class_id=class_id,
                gym_id=gym_id,
                class_name=tmpl["class_name"],
                class_description=tmpl["class_description"],
                image_url=tmpl["image_url"],
                max_capacity=max_capacity,
                points_worth=random.choice([25, 50, 75, 100]),
                is_active=is_active,
            )
        )

        current_shape = {
            "duration_minutes": tmpl["duration_minutes"],
            "recurring_unit": recurring_unit,
            "recurring_interval": 1,
            "start_date": start_date,
            "end_date": None,
            "weekday_slots": weekday_slots,
        }
        class_versions = _build_schedule_versions(
            class_id, gym_id, gym_timezone, current_shape, start_date, trainer_ids
        )
        schedules.extend(class_versions)

        # ~30% of classes get 1-2 single-instance exceptions, targeting a
        # real owned occurrence SLOT (whichever version owns it) so the
        # exception is never inert.
        if random.random() < 0.3:
            window_end = today + timedelta(days=FUTURE_SIGNUP_HORIZON_DAYS)
            owned_slots = [
                slot
                for slot in _owned_candidate_dates(class_versions, window_end)
                if slot[0] <= start_date + timedelta(days=60)
            ]
            used_slots: set[tuple[date, time]] = set()
            for _ in range(random.randint(1, 2)):
                available = [s for s in owned_slots if s not in used_slots]
                if not available:
                    break
                exc_date, exc_time = random.choice(available)
                used_slots.add((exc_date, exc_time))

                cancelled = random.random() < 0.5
                instance_exceptions.append(
                    ClassInstanceExceptionCreate(
                        exception_id=uuid.uuid4(),
                        class_id=class_id,
                        gym_id=gym_id,
                        original_date=exc_date,
                        original_time=exc_time,
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


# -- Slot construction (weekday_slots shapes) -------------------------------


def _random_slot_time() -> time:
    return time(random.randint(*_SLOT_HOUR_RANGE), random.choice(_SLOT_MINUTES))


def _random_distinct_slot_time(existing: set[time]) -> time:
    """A slot time not already in `existing` -- weekday_slots requires
    unique times per day (the shared canonicalizer + the live DB CHECK)."""
    candidate = _random_slot_time()
    while candidate in existing:
        candidate = _random_slot_time()
    return candidate


def _build_day_slots(
    trainer_ids: list[uuid.UUID], num_slots: int
) -> list[ScheduleSlot]:
    """`num_slots` distinct-time slots for one weekday_slots day (or the
    "all" key), each carrying an 80% chance of a random instructor. Times
    are forced distinct and returned sorted ascending, matching the stored
    shape canonicalize_weekday_slots produces.
    """
    times: set[time] = set()
    while len(times) < num_slots:
        times.add(_random_slot_time())
    return [
        ScheduleSlot(
            time=slot_time,
            instructor_id=(
                random.choice(trainer_ids)
                if trainer_ids and random.random() < 0.8
                else None
            ),
        )
        for slot_time in sorted(times)
    ]


def _build_weekday_slots(
    recurring_unit: RecurringUnit, trainer_ids: list[uuid.UUID]
) -> dict[str, list[ScheduleSlot]]:
    """The WHEN shape for a schedule version.

    Weekly picks 2-5 sampled weekdays, each with one slot; daily/monthly get
    exactly the reserved "all" key with one slot. A meaningful minority of
    classes (~MULTI_SLOT_CLASS_CHANCE) additionally get a genuine second
    slot -- a distinct time, independently possibly a distinct instructor --
    on ONE of their days (weekly: a random one of the sampled weekdays;
    daily/monthly: the single "all" day), so seeded data exercises the
    multi-time-per-day feature the runtime expander supports.
    """
    if recurring_unit == RecurringUnit.weekly:
        num_days = random.randint(2, 5)
        days = random.sample(DAYS, num_days)
        multi_slot_day = (
            random.choice(days)
            if random.random() < MULTI_SLOT_CLASS_CHANCE
            else None
        )
        return {
            d: _build_day_slots(trainer_ids, 2 if d == multi_slot_day else 1)
            for d in days
        }

    # daily / monthly -- every candidate date gets the "all" slot list.
    num_slots = 2 if random.random() < MULTI_SLOT_CLASS_CHANCE else 1
    return {ALL_SLOTS_KEY: _build_day_slots(trainer_ids, num_slots)}


# -- Schedule versioning ---------------------------------------------------


def _build_schedule_versions(
    class_id: uuid.UUID,
    gym_id: uuid.UUID,
    gym_timezone: str,
    current_shape: dict,
    start_date: date,
    trainer_ids: list[uuid.UUID],
) -> list[GymClassScheduleCreate]:
    """One (~70%) or two (~30%) append-only schedule versions for a class.

    A single-version class's one version is effective from a past instant
    around when its recurrence started (the FIRST version of a class owns
    occurrences back to negative infinity regardless -- see
    ClassesVersionExpander -- but a plausible value keeps the seeded row
    honest). A two-version class exercises the versioned past: v1 (a
    weekday_slots shape mutated by ONE change -- a shifted slot time, an
    added/removed slot, or a different weekday set -- everything else
    identical) is effective from that same early instant; v2 (the class's
    "current" shape, `current_shape`) takes over 1-6 weeks ago. Both freeze
    `gym_timezone` and share `start_date` (the recurrence anchor never moves
    -- only the shape, and when it took effect, differs). effective_from
    values are timezone-aware UTC datetimes, strictly increasing per class.
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

    earlier_shape = _vary_shape(current_shape, trainer_ids)
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


def _vary_shape(shape: dict, trainer_ids: list[uuid.UUID]) -> dict:
    """A prior version's shape: the current shape with ONE of its
    weekday_slots mutated -- a weekday toggled on/off (weekly only), one
    slot's time shifted, or one slot added/removed on a day -- everything
    else (duration, recurrence range) identical, a real historical schedule
    change without needing an independently-generated instructor lineup.
    Always leaves >=1 non-empty weekday_slots day (the live CHECK /
    ClassesCrudService._validate_weekly floor) and >=1 slot on every
    surviving day (a day key must never go empty -- omit it instead).
    """
    varied = dict(shape)
    weekday_slots = {
        day: list(slots) for day, slots in varied["weekday_slots"].items()
    }
    is_weekly = varied["recurring_unit"] == RecurringUnit.weekly
    mutations = (
        ["toggle_day", "shift_time", "add_remove_slot"]
        if is_weekly
        else ["shift_time", "add_remove_slot"]
    )
    mutation = random.choice(mutations)
    if mutation == "toggle_day":
        _toggle_weekday(weekday_slots, trainer_ids)
    elif mutation == "shift_time":
        _shift_one_slot_time(weekday_slots)
    else:
        _add_or_remove_one_slot(weekday_slots, trainer_ids)
    varied["weekday_slots"] = weekday_slots
    return varied


def _toggle_weekday(
    weekday_slots: dict[str, list[ScheduleSlot]], trainer_ids: list[uuid.UUID]
) -> None:
    """Flip one weekday's presence (weekly only): drop a day that had slots,
    or add one that didn't (a fresh single slot) -- guarantees a different
    active-day set. Never leaves the shape with zero active days (the live
    CHECK / ClassesCrudService._validate_weekly) -- flipping the only active
    day off instead flips a DIFFERENT day on so >=1 always survives.
    """
    day_to_flip = random.choice(DAYS)
    if day_to_flip in weekday_slots:
        del weekday_slots[day_to_flip]
    else:
        weekday_slots[day_to_flip] = _build_day_slots(trainer_ids, 1)
    if not weekday_slots:
        other_day = random.choice([d for d in DAYS if d != day_to_flip])
        weekday_slots[other_day] = _build_day_slots(trainer_ids, 1)


def _shift_one_slot_time(weekday_slots: dict[str, list[ScheduleSlot]]) -> None:
    """Shift one randomly-chosen existing slot's time by a random hour
    offset. A no-op on the rare collision with a sibling slot's time on the
    same day, rather than producing a duplicate-time day."""
    day = random.choice(list(weekday_slots.keys()))
    slots = weekday_slots[day]
    index = random.randrange(len(slots))
    old_time = slots[index].time
    offset = random.choice([-3, -2, -1, 1, 2, 3])
    new_time = time((old_time.hour + offset) % 24, old_time.minute)
    other_times = {slot.time for i, slot in enumerate(slots) if i != index}
    if new_time in other_times:
        return
    updated = list(slots)
    updated[index] = ScheduleSlot(
        time=new_time, instructor_id=slots[index].instructor_id
    )
    weekday_slots[day] = sorted(updated, key=lambda slot: slot.time)


def _add_or_remove_one_slot(
    weekday_slots: dict[str, list[ScheduleSlot]], trainer_ids: list[uuid.UUID]
) -> None:
    """Add a second slot to a single-slot day, or remove one slot from a
    multi-slot day -- exercises both directions of a multi-time-per-day
    change. Never empties a day (adds instead when it only has one slot)."""
    day = random.choice(list(weekday_slots.keys()))
    slots = weekday_slots[day]
    if len(slots) == 1:
        existing_times = {slot.time for slot in slots}
        new_time = _random_distinct_slot_time(existing_times)
        instructor_id = (
            random.choice(trainer_ids)
            if trainer_ids and random.random() < 0.8
            else None
        )
        weekday_slots[day] = sorted(
            [*slots, ScheduleSlot(time=new_time, instructor_id=instructor_id)],
            key=lambda slot: slot.time,
        )
    else:
        index = random.randrange(len(slots))
        weekday_slots[day] = [
            slot for i, slot in enumerate(slots) if i != index
        ]


# -- Pure recurrence enumeration (mirrors ClassesExpander) -----------------


def _weekday_short(d: date) -> str:
    """Map a date to its DAYS short name (Mon=0..Sun=6 -> "mon".."sun")."""
    return DAYS[(d.weekday() + 1) % 7]


def _slots_for(schedule: GymClassScheduleCreate, when: date) -> list[ScheduleSlot]:
    """`when`'s slot list -- the weekday key (weekly) or "all"
    (daily/monthly) -- mirrors ClassesExpander._slots_for."""
    key = (
        _weekday_short(when)
        if schedule.recurring_unit == RecurringUnit.weekly
        else ALL_SLOTS_KEY
    )
    return schedule.weekday_slots.get(key, [])


def _day_flag(schedule: GymClassScheduleCreate, when: date) -> bool:
    """Whether `schedule` occurs on `when`'s weekday (non-empty key) --
    mirrors ClassesExpander._day_flag."""
    return bool(schedule.weekday_slots.get(_weekday_short(when)))


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
                week_index % interval == 0 and _day_flag(schedule, cursor)
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
) -> dict[UUID, dict[tuple[date, time], ClassInstanceExceptionCreate]]:
    """Index instance exceptions by class_id, then by (original_date,
    original_time) -- the occurrence's permanent identity slot (unique per
    the DB constraint), so two same-day occurrences of one class are
    indexed independently."""
    by_class: dict[
        UUID, dict[tuple[date, time], ClassInstanceExceptionCreate]
    ] = defaultdict(dict)
    for exc in exceptions:
        by_class[exc.class_id][(exc.original_date, exc.original_time)] = exc
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


def _resolve_date(
    schedule: GymClassScheduleCreate,
    original_date: date,
    instance_exceptions: dict[tuple[date, time], ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
) -> list[_OccurrenceSnapshot]:
    """Fan one candidate date out over its slots and resolve each --
    mirrors ClassesExpander._resolve_date. A date carries every slot of its
    weekday key (weekly) or the "all" key (daily/monthly); each slot
    resolves independently against ITS OWN instance exception, keyed
    (original_date, original_time), so overriding one slot never touches a
    sibling slot on the same day.
    """
    snapshots: list[_OccurrenceSnapshot] = []
    for slot in _slots_for(schedule, original_date):
        snapshot = _resolve_slot(
            schedule,
            original_date,
            slot,
            instance_exceptions.get((original_date, slot.time)),
            range_exceptions,
        )
        if snapshot is not None:
            snapshots.append(snapshot)
    return snapshots


def _resolve_slot(
    schedule: GymClassScheduleCreate,
    original_date: date,
    slot: ScheduleSlot,
    instance: ClassInstanceExceptionCreate | None,
    range_exceptions: list[ClassRangeExceptionCreate],
) -> _OccurrenceSnapshot | None:
    """Resolve one (date, slot) against the class's seeded exceptions.
    Returns None ONLY when cancelled (an instance exception's cancel, or a
    covering range exception's cancel) -- mirrors
    ClassesExpander._resolve_slot with include_cancelled=False: a cancelled
    slot never "claims" its slot for cross-version dedup purposes. A
    reschedule keeps `original_date`/`original_time` as the identity and
    moves `emit_date`; the caller decides past-vs-future by `emit_date`, not
    `original_date`.
    """
    if instance is not None:
        if instance.is_cancelled:
            return None
        emit_date = instance.new_date if instance.new_date is not None else original_date
        return _OccurrenceSnapshot(
            original_date=original_date,
            original_time=slot.time,
            emit_date=emit_date,
            class_time=(
                instance.new_class_time
                if instance.new_class_time is not None
                else slot.time
            ),
            duration_minutes=(
                instance.new_duration_minutes
                if instance.new_duration_minutes is not None
                else schedule.duration_minutes
            ),
            instructor_id=(
                instance.new_instructor_id
                if instance.new_instructor_id is not None
                # No override -- the ORIGINAL slot's instructor (a moved
                # occurrence keeps its slot's instructor).
                else slot.instructor_id
            ),
        )

    covering = _covering_range(range_exceptions, original_date)
    if covering is not None:
        if covering.is_cancelled:
            return None
        return _OccurrenceSnapshot(
            original_date=original_date,
            original_time=slot.time,
            emit_date=original_date,
            class_time=slot.time,
            duration_minutes=schedule.duration_minutes,
            instructor_id=(
                covering.new_instructor_id
                if covering.new_instructor_id is not None
                else slot.instructor_id
            ),
        )

    return _OccurrenceSnapshot(
        original_date=original_date,
        original_time=slot.time,
        emit_date=original_date,
        class_time=slot.time,
        duration_minutes=schedule.duration_minutes,
        instructor_id=slot.instructor_id,
    )


def _expand_schedule(
    schedule: GymClassScheduleCreate,
    instance_exceptions: dict[tuple[date, time], ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
    until: date,
    max_count: int = 10_000,
) -> list[_OccurrenceSnapshot]:
    """One schedule version's full occurrence expansion (recurrence +
    exceptions), unfiltered by version ownership -- mirrors
    ClassesExpander.expand(). Callers apply the version-ownership window +
    slot-level dedup on top (`_owned_occurrences` / `_owned_candidate_dates`),
    exactly like ClassesVersionExpander wraps ClassesExpander.
    """
    snapshots: list[_OccurrenceSnapshot] = []
    for original_date in _enumerate_occurrences(schedule, until, max_count):
        snapshots.extend(
            _resolve_date(schedule, original_date, instance_exceptions, range_exceptions)
        )
    return snapshots


# -- Version ownership (mirrors ClassesVersionExpander) --------------------


def _original_start_at(
    schedule: GymClassScheduleCreate, when: date, slot_time: time
) -> datetime:
    """UTC instant of the (when, slot_time) slot under `schedule` -- mirrors
    ClassesVersionExpander.original_start_at (the version's OWN frozen tz)."""
    return datetime.combine(
        when, slot_time, tzinfo=ZoneInfo(schedule.timezone)
    ).astimezone(timezone.utc)


def _owned_candidate_dates(
    versions: list[GymClassScheduleCreate], window_end: date
) -> list[tuple[date, time]]:
    """Raw per-version recurrence (date, slot-time) candidates, owned +
    SLOT-level deduped -- no exceptions applied. Used to pick real
    occurrence slots for seeded exceptions before any exceptions exist.
    Mirrors the ownership-window + no-slot-doubling rules of
    ClassesVersionExpander, minus exception resolution.
    """
    ordered = sorted(versions, key=lambda v: v.effective_from)
    claimed: set[tuple[date, time]] = set()
    slots: list[tuple[date, time]] = []
    for i, version in enumerate(ordered):
        window_from = ordered[i].effective_from if i > 0 else None
        window_until = ordered[i + 1].effective_from if i + 1 < len(ordered) else None
        for original_date in _enumerate_occurrences(version, window_end, max_count=10_000):
            for slot in _slots_for(version, original_date):
                slot_key = (original_date, slot.time)
                slot_instant = _original_start_at(version, original_date, slot.time)
                if window_from is not None and slot_instant < window_from:
                    continue
                if window_until is not None and slot_instant >= window_until:
                    continue
                if slot_key in claimed:
                    continue
                claimed.add(slot_key)
                slots.append(slot_key)
    slots.sort()
    return slots


def _owned_occurrences(
    versions: list[GymClassScheduleCreate],
    instance_exceptions: dict[tuple[date, time], ClassInstanceExceptionCreate],
    range_exceptions: list[ClassRangeExceptionCreate],
    window_end: date,
) -> list[_OccurrenceSnapshot]:
    """All of a class's resolved occurrences across its schedule versions,
    honoring ownership windows + earliest-version-wins SLOT-level dedup --
    mirrors ClassesVersionExpander.expand(). Bounded above by `window_end`
    (today + the future sign-up horizon); each version's own `start_date`
    bounds it below. A cancelled candidate never claims its slot (matching
    the live expander's include_cancelled=False semantics), so a different
    version may claim the same slot instead. Dedup is deliberately
    SLOT-level (not day-level): a boundary day may legitimately carry both
    versions' different-time slots.
    """
    ordered = sorted(versions, key=lambda v: v.effective_from)
    claimed: set[tuple[date, time]] = set()
    resolved: list[_OccurrenceSnapshot] = []
    for i, version in enumerate(ordered):
        window_from = ordered[i].effective_from if i > 0 else None
        window_until = ordered[i + 1].effective_from if i + 1 < len(ordered) else None
        expanded = _expand_schedule(
            version, instance_exceptions, range_exceptions, window_end
        )
        for snapshot in expanded:
            slot_key = (snapshot.original_date, snapshot.original_time)
            slot_instant = _original_start_at(
                version, snapshot.original_date, snapshot.original_time
            )
            if window_from is not None and slot_instant < window_from:
                continue
            if window_until is not None and slot_instant >= window_until:
                continue
            if slot_key in claimed:
                continue
            claimed.add(slot_key)
            resolved.append(snapshot)
    resolved.sort(key=lambda s: (s.original_date, s.original_time))
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

    A member's subset is capped at MAX_CLASSES_ATTENDED_PER_MEMBER.
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

        n_attended = random.randint(
            1, min(MAX_CLASSES_ATTENDED_PER_MEMBER, len(eligible))
        )
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


def award_attendance_points(
    members: list[MemberCreate],
    classes: list[GymClassCreate],
    attendance: list[MemberAttendanceCreate],
) -> dict[UUID, int]:
    """Give each member the points their seeded attendance earned them.

    The seed's mirror of the live check-in side-effect (each attendance adds
    its class's `points_worth`), so a balance is a figure a CRM reader can add
    up from the member's own attendance list.

    Mutates `MemberCreate.points_balance` in place and returns the
    {member_id: balance} write-back map -- a member with no attendance is
    absent, their row already holding 0.

    Assignment, not accumulation, so a second call over the same attendance is
    a no-op rather than a double award. Must run BEFORE redemptions, which
    debit this earned total.
    """
    points_worth = {cls.class_id: cls.points_worth for cls in classes}
    earned: dict[UUID, int] = defaultdict(int)
    for row in attendance:
        earned[row.member_id] += points_worth[row.class_id]
    for member in members:
        if member.member_id in earned:
            member.points_balance = earned[member.member_id]
    return dict(earned)


def _effective_capacity(
    cls: GymClassCreate,
    instances_by_class: dict[
        UUID, dict[tuple[date, time], ClassInstanceExceptionCreate]
    ],
    original_date: date,
    original_time: time,
) -> int | None:
    """The class's max_capacity, overridden per-occurrence SLOT by an
    instance exception's new_max_capacity when one is set for that ORIGINAL
    (date, time) slot (instance exceptions are keyed by the original slot,
    not the effective/post-reschedule one). None means unlimited -- never
    blocks. Mirrors SignupService._effective_capacity's resolution (class
    default, exception override wins) on the live path.
    """
    exc = instances_by_class.get(cls.class_id, {}).get(
        (original_date, original_time)
    )
    if exc is not None and exc.new_max_capacity is not None:
        return exc.new_max_capacity
    return cls.max_capacity


def _past_signups_for_occurrence(
    gym_id: uuid.UUID,
    cls: GymClassCreate,
    occ: _OccurrenceSnapshot,
    attended_ids: list[UUID],
    instances_by_class: dict[
        UUID, dict[tuple[date, time], ClassInstanceExceptionCreate]
    ],
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
        cls, instances_by_class, occ.original_date, occ.original_time
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
    instances_by_class: dict[
        UUID, dict[tuple[date, time], ClassInstanceExceptionCreate]
    ],
    member_ids: list[UUID],
) -> list[ClassSignupCreate]:
    """Sign-ups-only for a not-yet-occurred occurrence -- no attendance
    exists yet. Respects the occurrence's effective max_capacity as the draw
    pool's cap.
    """
    if not member_ids:
        return []
    effective_capacity = _effective_capacity(
        cls, instances_by_class, occ.original_date, occ.original_time
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

    attendance_by_occurrence: dict[
        tuple[UUID, date, time], list[UUID]
    ] = defaultdict(list)
    for a in attendance:
        attendance_by_occurrence[
            (a.class_id, a.original_date, a.original_time)
        ].append(a.member_id)

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
                    (cls.class_id, occ.original_date, occ.original_time), []
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
