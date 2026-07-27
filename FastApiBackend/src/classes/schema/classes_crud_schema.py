"""Pydantic models for the class + exception CRUD and schedule-board reads.

* ``gym_classes`` create / update / response. A class is IDENTITY
  (``gym_classes``) plus an append-only versioned SCHEDULE shape
  (``gym_class_schedules``): the create request carries both halves flat; the
  update request splits them by destination (identity = UPDATE in place,
  schedule = mint a NEW version) — the discounts identity/values precedent.
  Responses stay flat (identity + the CURRENT version). The schedule's WHEN
  is ``weekday_slots`` — day -> ordered slot list, several times per day
  allowed, each slot with its own optional instructor (resolved to a display
  name in responses via one gym-employees lookup).
* ``class_instance_exceptions`` upsert / response (single-slot overrides,
  keyed unique per ``(class_id, original_date, original_time)``).
* ``class_range_exceptions`` create / response (cancel-or-substitute over a
  continuous range).
* ``EffectiveClassInstanceResponse`` — the schedule-board shape, one row per
  effective dated occurrence after the version expander applies ownership +
  recurrence + exceptions (cancelled occurrences included, flagged).

The recurring-unit enum is reused from the Database package
(``schema.gym_class.RecurringUnit``) — never redefined here.
"""

from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field, model_validator
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import (
    ClassSlot,
    canonicalize_weekday_slots,
)
from src.shared.partial_model import partial_model


class GymClassIdentityFields(BaseModel):
    """The writable ``gym_classes`` IDENTITY columns — what the class is, who
    may attend, what it's worth. Identity applies across all schedule
    versions (a rename renames the past too)."""

    class_name: str = Field(min_length=1)
    class_description: str | None = None
    max_capacity: int | None = Field(default=None, gt=0)
    allowed_plan_ids: list[UUID] | None = None
    image_url: str | None = None
    points_worth: int = Field(default=50, gt=0)


class GymClassScheduleFields(BaseModel):
    """The schedule SHAPE — one complete ``gym_class_schedules`` version body
    (minus the backend-stamped ``effective_from`` / ``timezone``). Always
    submitted whole: a schedule edit mints a new version, never patches one.

    ``weekday_slots`` runs through the SAME canonicalizer as the expander's
    DB-row contract (``classes_expander_schema.canonicalize_weekday_slots``),
    so an API submission and a stored shape can never disagree on validity or
    ordering: weekly -> sun..sat keys only (>=1); daily/monthly -> exactly
    the reserved ``"all"`` key; no empty lists, no duplicate times; lists
    sorted ascending by time.
    """

    duration_minutes: int = Field(gt=0)
    recurring_unit: RecurringUnit
    recurring_interval: int = Field(default=1, gt=0)
    weekday_slots: dict[str, list[ClassSlot]]
    start_date: date
    end_date: date | None = None

    @model_validator(mode="after")
    def _canonicalize_slots(self) -> "GymClassScheduleFields":
        self.weekday_slots = canonicalize_weekday_slots(
            self.weekday_slots, self.recurring_unit
        )
        return self


class GymClassCreateRequest(GymClassIdentityFields, GymClassScheduleFields):
    """Body for POST /api/v1/classes — create a gym class.

    Flat: both the identity columns and the full schedule shape, exactly the
    old single-table payload. The service writes the identity row and mints
    the FIRST schedule version in one transaction. ``is_active`` /
    ``is_deleted`` are not accepted (they default TRUE / FALSE and are managed
    by the soft-delete path). A future ``start_date`` is the supported way to
    launch a class ahead of time — nothing renders before it.
    """

    gym_id: UUID


# Identity update body: every identity column made optional (the service
# writes only the keys in ``model_fields_set``, so a provided ``None`` clears
# a column and an absent field is untouched; the change keys are validated
# against the ``GYM_CLASSES`` immutable frozenset before any write), plus
# ``is_active``. ``is_deleted`` is deliberately NOT accepted here — deletion
# goes through DELETE /classes/{id}, which also runs the future-keyed wipe.
GymClassIdentityUpdateData = partial_model(
    "GymClassIdentityUpdateData",
    GymClassIdentityFields,
    extra={
        "is_active": (bool | None, None),
    },
)


class GymClassUpdateRequest(BaseModel):
    """Body for PUT /api/v1/classes/{class_id} — split by destination.

    ``identity`` (partial) updates ``gym_classes`` in place; ``schedule`` (a
    COMPLETE shape) mints a new ``gym_class_schedules`` version effective now
    — running the version-change wipe over future-keyed rows whose original
    slot the new version no longer produces. Either half may be omitted; a
    ``schedule`` deep-equal to the current version is a no-op (no mint, no
    wipe). Mirrors the discounts identity/values update split.
    """

    identity: GymClassIdentityUpdateData | None = None
    schedule: GymClassScheduleFields | None = None


class ClassSlotResponse(BaseModel):
    """One ``weekday_slots`` slot with its instructor resolved for display.

    ``instructor_name`` is ``first_name last_name`` from ``gym_employees``
    (None when the slot has no instructor or the employee is gone).
    """

    time: time
    instructor_id: UUID | None
    instructor_name: str | None


class GymClassResponse(BaseModel):
    """A single ``gym_classes`` row flattened with its CURRENT schedule
    version — ``weekday_slots`` carries the per-slot instructor resolved to a
    display name (one gym-employees lookup, merged in the service)."""

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: str | None
    duration_minutes: int
    recurring_unit: RecurringUnit
    recurring_interval: int
    weekday_slots: dict[str, list[ClassSlotResponse]]
    start_date: date
    end_date: date | None
    max_capacity: int | None
    allowed_plan_ids: list[UUID] | None
    # Never None: gym_classes.image_url is NOT NULL (writers fill the
    # platform default when no image is provided).
    image_url: str
    points_worth: int
    is_active: bool
    is_deleted: bool
    created_at: datetime


class GymClassListResponse(BaseModel):
    """List of gym classes."""

    items: list[GymClassResponse]


class ClassInstanceExceptionUpsertRequest(BaseModel):
    """Body for POST /api/v1/classes/{class_id}/exceptions/instance.

    Upserts the single-SLOT override keyed unique per ``(class_id,
    original_date, original_time)`` — with several slots per day legal, the
    pair names exactly one occurrence. ``new_date`` (reschedule target) may
    be any date — past, today, or future — and may not collide with an
    existing non-cancelled occurrence at the exact target instant (new_date +
    start time; enforced by the service, which also moves the occurrence's
    attendance).
    """

    original_date: date
    original_time: time
    is_cancelled: bool = False
    new_class_time: time | None = None
    new_duration_minutes: int | None = Field(default=None, gt=0)
    new_max_capacity: int | None = Field(default=None, gt=0)
    new_instructor_id: UUID | None = None
    new_date: date | None = None


class ClassInstanceExceptionResponse(BaseModel):
    """A single ``class_instance_exceptions`` row."""

    exception_id: UUID
    class_id: UUID
    gym_id: UUID
    original_date: date
    original_time: time
    is_cancelled: bool
    new_class_time: time | None
    new_duration_minutes: int | None
    new_max_capacity: int | None
    new_instructor_id: UUID | None
    new_date: date | None
    created_at: datetime


class ClassInstanceExceptionListResponse(BaseModel):
    """List of instance exceptions for a class."""

    items: list[ClassInstanceExceptionResponse]


class ClassRangeExceptionCreateRequest(BaseModel):
    """Body for POST /api/v1/classes/{class_id}/exceptions/range.

    A range exception must either cancel the range or substitute an instructor
    across it (``is_cancelled`` OR ``new_instructor_id`` — the DB CHECK, also
    enforced up front by the service for a clean 400).
    """

    start_date: date
    end_date: date
    is_cancelled: bool = False
    new_instructor_id: UUID | None = None


class ClassRangeExceptionResponse(BaseModel):
    """A single ``class_range_exceptions`` row."""

    exception_id: UUID
    class_id: UUID
    gym_id: UUID
    start_date: date
    end_date: date
    is_cancelled: bool
    new_instructor_id: UUID | None
    created_at: datetime


class ClassRangeExceptionListResponse(BaseModel):
    """List of range exceptions for a class."""

    items: list[ClassRangeExceptionResponse]


class ClassRangeExceptionUpdateRequest(BaseModel):
    """Body for PUT /api/v1/classes/{class_id}/exceptions/range/{exception_id}.

    Moves the range's dates only — ``is_cancelled`` / ``new_instructor_id``
    are fixed at creation (create a new range instead of changing what kind
    of range it is). For a CANCEL range, the write atomically re-runs the
    create path's teardown over the NEW ``[start_date, end_date]`` — see
    ``ClassesExceptionsService.update_range_exception``. Dates that fall OUT
    of the new coverage are never explicitly restored; they simply stop
    being covered on the next expansion.
    """

    start_date: date
    end_date: date


class EffectiveClassInstanceResponse(BaseModel):
    """One effective dated class occurrence for the schedule board.

    Produced by the version expander (ownership + recurrence + exceptions
    applied, ``include_cancelled=True``) and enriched from the class identity
    row, the gym's employees, and the attendance/sign-up counts.

    Attributes:
        class_id: The owning class.
        gym_id: The owning gym.
        class_name: The class's display name.
        class_date: The effective (post-reschedule) local date.
        original_date: The occurrence's IDENTITY date — the owning schedule
            version's pre-exception slot date. Every occurrence-addressed
            call (check-in, sign-up, exception, cancel, reschedule) passes
            THIS date, never ``class_date``.
        original_time: The occurrence's IDENTITY time — the owning version's
            pre-exception slot time. With several slots per day legal,
            ``(original_date, original_time)`` is the full occurrence key;
            occurrence-addressed calls pass BOTH, never the effective
            ``resolved_class_time``.
        occurred_at: UTC, timezone-aware start instant.
        resolved_class_time: Effective local start time (override or default).
        resolved_duration_minutes: Effective length (override or default).
        resolved_instructor_id: Effective instructor (override or weekday
            default); None when no instructor is assigned.
        resolved_instructor_name: ``first_name last_name`` for the resolved
            instructor (None when unassigned or not found).
        class_description: The class's description text
            (``gym_classes.class_description``); None when the class has none.
        resolved_instructor_bio: The resolved instructor's public bio
            (``gym_employees.employee_public_description``); None when
            unassigned, not found, or the instructor has no bio.
        resolved_instructor_image_url: The resolved instructor's photo URL
            (``gym_employees.employee_pic_url``); None when unassigned, not
            found, or the instructor has no photo.
        image_url: The class image, if any.
        points_worth: Points awarded for attending.
        is_active: The owning class's live/PAUSED flag. Only ever False on
            an ``include_inactive=true`` read, which mixes paused and live
            rows — which is why it is on the wire: the CRM's classes page
            marks a paused card and routes its tap to the editor.
        max_capacity: Class capacity (None = unlimited).
        is_cancelled: True when this occurrence is cancelled (still shown).
        has_instance_exception: True when an instance exception exists on this
            occurrence's exact original slot.
        has_range_exception: True when a range exception covers this
            occurrence's original date.
        cancelling_range_id: The range exception (``class_range_exceptions
            .exception_id``) that actually cancelled this occurrence, per the
            expander's own precedence resolution — set ONLY when a RANGE
            exception (not an instance exception) is what cancelled it; None
            for an instance-cancel and for a non-cancelled occurrence. Lets
            the CRM tell a range-cancelled occurrence apart from an
            instance-cancelled one and jump to editing the governing range.
        attendance_count: Recorded attendance for this occurrence (0 when
            none).
        signup_count: Members signed up (reserved) for this occurrence — 0
            when none. Shown for both future AND past occurrences (a sign-up
            can be created ahead of a class that hasn't run yet, and the past
            count is a record of how many reserved a class that already ran).
    """

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_date: date
    original_date: date
    original_time: time
    occurred_at: datetime
    resolved_class_time: time
    resolved_duration_minutes: int
    resolved_instructor_id: UUID | None
    resolved_instructor_name: str | None
    class_description: str | None = None
    resolved_instructor_bio: str | None = None
    resolved_instructor_image_url: str | None = None
    image_url: str
    points_worth: int
    is_active: bool
    max_capacity: int | None
    is_cancelled: bool
    has_instance_exception: bool
    has_range_exception: bool
    cancelling_range_id: UUID | None = None
    attendance_count: int = 0
    signup_count: int = 0


class EffectiveClassInstanceListResponse(BaseModel):
    """The schedule-board feed: effective occurrences across a date window."""

    items: list[EffectiveClassInstanceResponse]
