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

from pydantic import BaseModel
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path


class ExpanderClass(BaseModel):
    """One recurring-schedule SHAPE, as the single-shape expander needs it.

    A flat projection of a ``gym_class_schedules`` row's shape columns: the
    seven ``sun``..``sat`` day flags and the seven
    ``sun_instructor_id``..``sat_instructor_id`` per-day instructor slots are
    kept flat (not nested) so a DB row maps in directly. The versioned
    contract (``ExpanderScheduleVersion``) extends this with the version
    identity (``schedule_id`` / ``effective_from`` / ``timezone``).

    Attributes:
        class_id: The class this schedule belongs to.
        gym_id: The owning gym.
        class_time: Default local time-of-day the class starts.
        duration_minutes: Default length in minutes.
        recurring_unit: ``daily`` / ``weekly`` / ``monthly`` recurrence.
        recurring_interval: Every Nth unit fires (1 = every unit).
        sun..sat: Per-weekday flags (weekly only; ignored for daily/monthly).
        sun_instructor_id..sat_instructor_id: Per-weekday default instructor.
        start_date: The recurrence anchor; all counting is relative to this.
        end_date: Last eligible date (inclusive); None = open-ended.
    """

    class_id: UUID
    gym_id: UUID
    class_time: time
    duration_minutes: int
    recurring_unit: RecurringUnit
    recurring_interval: int = 1
    sun: bool = False
    mon: bool = False
    tue: bool = False
    wed: bool = False
    thu: bool = False
    fri: bool = False
    sat: bool = False
    sun_instructor_id: UUID | None = None
    mon_instructor_id: UUID | None = None
    tue_instructor_id: UUID | None = None
    wed_instructor_id: UUID | None = None
    thu_instructor_id: UUID | None = None
    fri_instructor_id: UUID | None = None
    sat_instructor_id: UUID | None = None
    start_date: date
    end_date: date | None = None


class ExpanderScheduleVersion(ExpanderClass):
    """One append-only ``gym_class_schedules`` version row.

    The shape fields come from ``ExpanderClass``; this adds the version
    identity. A version OWNS the occurrences whose ORIGINAL instant
    (``original_date`` + ``class_time`` in the version's own frozen
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
    """A single-occurrence override keyed to one ``original_date``.

    The DB enforces at most one instance exception per (class, original_date),
    so ``original_date`` is the unique key the expander indexes on. An instance
    exception on a date is authoritative for that date and suppresses any range
    exception covering it.

    Attributes:
        original_date: The scheduled date this exception applies to.
        is_cancelled: When True, the occurrence is dropped entirely.
        new_class_time: Override start time (None = keep class default).
        new_duration_minutes: Override length (None = keep class default).
        new_instructor_id: Override instructor (None = the original date's
            weekday instructor — a moved occurrence keeps its slot's
            instructor).
        new_date: Reschedule target (None = not rescheduled).
        created_at: Row creation timestamp (carried for completeness; instance
            exceptions are unique per date so no tie-break is needed).
    """

    original_date: date
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
        start_date: First covered date (inclusive).
        end_date: Last covered date (inclusive).
        is_cancelled: When True, every covered occurrence is dropped.
        new_instructor_id: Substitute instructor across the range (None = the
            original date's weekday instructor).
        created_at: Row creation timestamp — the overlap tie-breaker.
    """

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
    schedule_id: UUID | None = None
    original_start_at: datetime | None = None
