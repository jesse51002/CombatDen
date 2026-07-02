"""Input contracts and output model for the class recurrence expanders.

These are intentionally minimal, standalone Pydantic models so the expanders
(``ClassesExpander`` — one schedule shape; ``ClassesVersionExpander`` — a
class's full version history) have NO forward dependency on the class-CRUD
schemas. Services map DB rows (``gym_class_schedules`` /
``class_instance_exceptions`` / ``class_range_exceptions``) into these
contracts before calling the expanders; every consumer (board reads, check-in
validation, sign-up validation, reschedule checks, the version-change wipe)
consumes the same ``EffectiveOccurrence`` output, so this is the one
authoritative shape.

The recurring-unit enum is reused from the Database package
(``schema.gym_class.RecurringUnit``) — never redefined here.
"""

from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, model_validator
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path

# The reserved weekday_slots key daily/monthly schedules use: every candidate
# date gets the "all" list's slots (weekly schedules use sun..sat keys only).
ALL_DAYS_KEY = "all"

# Canonical key order for a canonicalized weekday_slots mapping.
WEEKDAY_SLOT_KEYS = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")


class ClassSlot(BaseModel):
    """One (time, instructor) slot inside a schedule's ``weekday_slots``.

    Attributes:
        time: Local start time of this slot — together with the occurrence
            date it is the occurrence's permanent identity time.
        instructor_id: This slot's default instructor (None = unassigned).
    """

    time: time
    instructor_id: UUID | None = None


def canonicalize_weekday_slots(
    weekday_slots: dict[str, list[ClassSlot]],
    recurring_unit: RecurringUnit,
) -> dict[str, list[ClassSlot]]:
    """Validate + canonicalize one ``weekday_slots`` mapping.

    The ONE slot-shape authority — both boundaries run it: API submissions
    (``GymClassScheduleFields``) and DB-row parsing (``ExpanderClass``, which
    every ``gym_class_schedules`` read maps into), so a stored shape and a
    submitted shape can never disagree on validity or ordering.

    Rules:
        * weekly -> only ``sun``..``sat`` keys, at least one present;
          daily/monthly -> exactly the reserved ``"all"`` key.
        * a present key's list must be non-empty (omit the key instead) and
          free of duplicate times.
        * every list is returned sorted ascending by time and the keys in
          canonical (sun..sat) order, so two equal shapes compare equal
          (``==``) regardless of submission / JSONB order — what the mint
          engine's deep-equal no-op check relies on.

    Raises:
        ValueError: On any shape violation (surfaces as a 422 through the
            Pydantic validators that call this).
    """
    allowed = (
        set(WEEKDAY_SLOT_KEYS)
        if recurring_unit == RecurringUnit.weekly
        else {ALL_DAYS_KEY}
    )
    for key, slots in weekday_slots.items():
        if key not in allowed:
            raise ValueError(
                f"weekday_slots key {key!r} is invalid for a "
                f"{recurring_unit} schedule"
            )
        if not slots:
            raise ValueError(
                f"weekday_slots[{key!r}] must not be empty — omit the key"
            )
        times = [slot.time for slot in slots]
        if len(times) != len(set(times)):
            raise ValueError(f"weekday_slots[{key!r}] has duplicate times")
    if recurring_unit == RecurringUnit.weekly and not weekday_slots:
        raise ValueError("A weekly schedule must have at least one weekday")
    if recurring_unit != RecurringUnit.weekly and ALL_DAYS_KEY not in weekday_slots:
        raise ValueError(
            f'A {recurring_unit} schedule must put its slots under "all"'
        )
    key_order = (*WEEKDAY_SLOT_KEYS, ALL_DAYS_KEY)
    return {
        key: sorted(weekday_slots[key], key=lambda slot: slot.time)
        for key in key_order
        if key in weekday_slots
    }


class ExpanderClass(BaseModel):
    """One recurring-schedule SHAPE, as the single-shape expander needs it.

    A projection of a ``gym_class_schedules`` row's shape columns. The
    versioned contract (``ExpanderScheduleVersion``) extends this with the
    version identity (``schedule_id`` / ``effective_from`` / ``timezone``).

    Attributes:
        class_id: The class this schedule belongs to.
        gym_id: The owning gym.
        duration_minutes: Length in minutes (version-level — shared by every
            slot).
        recurring_unit: ``daily`` / ``weekly`` / ``monthly`` recurrence.
        recurring_interval: Every Nth unit fires (1 = every unit).
        weekday_slots: WHEN the class occurs — day -> ordered slot list, so a
            class may occur several times on one day. Weekly uses sun..sat
            keys (a day occurs iff its key holds a non-empty list);
            daily/monthly use exactly the reserved ``"all"`` key. Validated +
            canonicalized (sorted, deduped) on construction.
        start_date: The recurrence anchor; all counting is relative to this.
        end_date: Last eligible date (inclusive); None = open-ended.
    """

    class_id: UUID
    gym_id: UUID
    duration_minutes: int
    recurring_unit: RecurringUnit
    recurring_interval: int = 1
    weekday_slots: dict[str, list[ClassSlot]]
    start_date: date
    end_date: date | None = None

    @model_validator(mode="after")
    def _canonicalize_slots(self) -> "ExpanderClass":
        self.weekday_slots = canonicalize_weekday_slots(
            self.weekday_slots, self.recurring_unit
        )
        return self


class ExpanderScheduleVersion(ExpanderClass):
    """One append-only ``gym_class_schedules`` version row.

    The shape fields come from ``ExpanderClass``; this adds the version
    identity. A version OWNS the occurrences whose ORIGINAL instant
    (``original_date`` + the slot's time in the version's own frozen
    ``timezone``) falls inside ``[effective_from, next version's
    effective_from)`` — the window end is derived from the class's next
    version, never stored.

    Attributes:
        schedule_id: The version row's identity.
        effective_from: When this version starts owning occurrences
            (server-stamped at mint; never future, never edited).
        timezone: IANA zone frozen at mint — the version always expands with
            its OWN zone, so a later gym timezone change can never move any
            existing version's occurrences.
    """

    schedule_id: UUID
    effective_from: datetime
    timezone: str


class ExpanderInstanceException(BaseModel):
    """A single-occurrence override bound to ONE original slot.

    The DB enforces at most one instance exception per (class, original_date,
    original_time), so the (date, time) pair is the unique key the expander
    indexes on — two same-day occurrences of one class are overridden
    independently. An instance exception on a slot is authoritative for that
    slot and suppresses any range exception covering its date.

    Attributes:
        original_date: The scheduled date this exception applies to.
        original_time: The bound slot's identity time on that date.
        is_cancelled: When True, the occurrence is dropped entirely.
        new_class_time: Override start time (None = keep the slot's time).
        new_duration_minutes: Override length (None = keep class default).
        new_instructor_id: Override instructor (None = the original slot's
            instructor — a moved occurrence keeps its slot's instructor).
        new_date: Reschedule target (None = not rescheduled).
        created_at: Row creation timestamp (carried for completeness; instance
            exceptions are unique per slot so no tie-break is needed).
    """

    original_date: date
    original_time: time
    is_cancelled: bool = False
    new_class_time: time | None = None
    new_duration_minutes: int | None = None
    new_instructor_id: UUID | None = None
    new_date: date | None = None
    created_at: datetime


class ExpanderRangeException(BaseModel):
    """A cancel-or-substitute override across a continuous date range.

    When several range exceptions overlap a date, the earliest-created one wins
    (the expander sorts by ``created_at`` and takes the first that covers).

    Attributes:
        exception_id: The row's own identity — threaded onto a cancelled
            occurrence's ``cancelling_range_id`` (see ``EffectiveOccurrence``)
            so a caller can tell WHICH range cancelled it, for the CRM's
            range-exception edit surfaces.
        start_date: First covered date (inclusive).
        end_date: Last covered date (inclusive).
        is_cancelled: When True, every covered occurrence is dropped.
        new_instructor_id: Substitute instructor across the range (None = the
            original date's weekday instructor).
        created_at: Row creation timestamp — the overlap tie-breaker.
    """

    exception_id: UUID
    start_date: date
    end_date: date
    is_cancelled: bool = False
    new_instructor_id: UUID | None = None
    created_at: datetime


class EffectiveOccurrence(BaseModel):
    """One effective, dated class occurrence after recurrence + exceptions.

    Attributes:
        original_date: The scheduled (pre-reschedule) recurrence date.
        original_time: The owning schedule's default start time BEFORE any
            exception — ``(original_date, original_time)`` is the occurrence's
            permanent identity key (what attendance / sign-ups store; what the
            version-change exact-slot match compares).
        effective_date: Where the occurrence actually lands —
            ``original_date`` unless an instance exception rescheduled it.
        occurred_at: UTC, timezone-aware start instant (the effective local
            date + time converted from the schedule's timezone).
        class_time: Effective local start time (override or class default).
        duration_minutes: Effective length (override or class default).
        instructor_id: Effective instructor (override or weekday default;
            None when no instructor is assigned to that slot).
        is_rescheduled: True when an instance exception moved this occurrence
            to a ``new_date``.
        is_cancelled: True when this occurrence was cancelled (by an instance
            or a covering range exception) but is still emitted for display.
            Only ever True when ``expand(..., include_cancelled=True)``; the
            default expand drops cancelled occurrences entirely. A cancelled
            occurrence carries the class's default time / duration / instructor
            (the overrides are irrelevant once cancelled) and stays on its
            ``original_date`` (never rescheduled).
        cancelling_range_id: The ``class_range_exceptions.exception_id`` that
            cancelled this occurrence — set ONLY when a RANGE exception (not
            an instance exception) is what cancelled it; None for an
            instance-cancel and for a non-cancelled occurrence. Lets a caller
            (the CRM's occurrence screen) distinguish a range-cancelled day
            from an instance-cancelled one and jump straight to editing the
            governing range.
        schedule_id: The OWNING version row (set by the version expander;
            None when a single shape was expanded directly).
        original_start_at: UTC instant of the ORIGINAL slot
            (``original_date`` + ``original_time`` in the owning version's
            timezone) — the instant the ownership windowing tested (set by
            the version expander; None when a single shape was expanded
            directly).
    """

    original_date: date
    original_time: time
    effective_date: date
    occurred_at: datetime
    class_time: time
    duration_minutes: int
    instructor_id: UUID | None
    is_rescheduled: bool
    is_cancelled: bool = False
    cancelling_range_id: UUID | None = None
    schedule_id: UUID | None = None
    original_start_at: datetime | None = None
