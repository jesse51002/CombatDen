"""Pydantic models for the class + exception CRUD and schedule-board reads.

These cover Phase 3 of the class system:

* ``gym_classes`` create / update / response (recurrence embedded; the seven
  per-weekday instructor slots resolve to display names joined from
  ``gym_employees``).
* ``class_instance_exceptions`` upsert / response (single-date overrides, keyed
  unique per ``(class_id, original_date)``).
* ``class_range_exceptions`` create / response (cancel-or-substitute over a
  continuous range).
* ``EffectiveClassInstanceResponse`` — the schedule-board shape, one row per
  effective dated occurrence after the expander applies recurrence + exceptions
  (cancelled occurrences included, flagged).

The recurring-unit enum is reused from the Database package
(``schema.gym_class.RecurringUnit``) — never redefined here.
"""

from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.shared.partial_model import partial_model


class GymClassFields(BaseModel):
    """The writable ``gym_classes`` columns — defined ONCE, shared by create
    and update so the long field list can't drift between them.

    ``GymClassCreateRequest`` inherits this (fields keep their declared
    required-ness); ``GymClassUpdateData`` is the all-optional partial derived
    from it via :func:`partial_model`. The recurrence is embedded, and the seven
    per-weekday instructor slots are nullable.
    """

    class_name: str = Field(min_length=1)
    class_description: str | None = None
    class_time: time
    duration_minutes: int = Field(gt=0)
    recurring_unit: RecurringUnit
    recurring_interval: int = Field(default=1, gt=0)
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
    max_capacity: int | None = Field(default=None, gt=0)
    allowed_plan_ids: list[UUID] | None = None
    image_url: str | None = None
    points_worth: int = Field(default=50, gt=0)


class GymClassCreateRequest(GymClassFields):
    """Body for POST /api/v1/classes — create a gym class.

    The writable columns are inherited from ``GymClassFields``. ``is_active`` /
    ``is_deleted`` are not accepted (they default TRUE / FALSE and are managed
    by the soft-delete path).
    """

    gym_id: UUID


# Update body: every ``GymClassFields`` column made optional (the service writes
# only the keys in ``model_fields_set``, so a provided ``None`` clears a column
# and an absent field is untouched; the change keys are validated against the
# ``GYM_CLASSES`` immutable frozenset before any write), plus the two status
# flags only an update may set. Derived from the one field definition above, so
# it can never drift from ``GymClassCreateRequest``.
GymClassUpdateData = partial_model(
    "GymClassUpdateData",
    GymClassFields,
    extra={
        "is_active": (bool | None, None),
        "is_deleted": (bool | None, None),
    },
)


class GymClassUpdateRequest(BaseModel):
    """Body for PUT /api/v1/classes/{class_id}."""

    data: GymClassUpdateData


class GymClassResponse(BaseModel):
    """A single ``gym_classes`` row with resolved per-weekday instructor names.

    The seven ``*_instructor_name`` fields are the joined
    ``first_name || ' ' || last_name`` from ``gym_employees`` for each weekday's
    instructor slot (``None`` when that slot has no instructor).
    """

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: str | None
    class_time: time
    duration_minutes: int
    recurring_unit: RecurringUnit
    recurring_interval: int
    sun: bool
    mon: bool
    tue: bool
    wed: bool
    thu: bool
    fri: bool
    sat: bool
    sun_instructor_id: UUID | None
    mon_instructor_id: UUID | None
    tue_instructor_id: UUID | None
    wed_instructor_id: UUID | None
    thu_instructor_id: UUID | None
    fri_instructor_id: UUID | None
    sat_instructor_id: UUID | None
    sun_instructor_name: str | None
    mon_instructor_name: str | None
    tue_instructor_name: str | None
    wed_instructor_name: str | None
    thu_instructor_name: str | None
    fri_instructor_name: str | None
    sat_instructor_name: str | None
    start_date: date
    end_date: date | None
    max_capacity: int | None
    allowed_plan_ids: list[UUID] | None
    image_url: str | None
    points_worth: int
    is_active: bool
    is_deleted: bool
    created_at: datetime


class GymClassListResponse(BaseModel):
    """List of gym classes."""

    items: list[GymClassResponse]


class ClassInstanceExceptionUpsertRequest(BaseModel):
    """Body for POST /api/v1/classes/{class_id}/exceptions/instance.

    Upserts the single-date override keyed unique per ``(class_id,
    original_date)``. ``new_date`` (reschedule target) may be any date — past,
    today, or future — and may not collide with an existing non-cancelled
    occurrence at the exact target instant (new_date + start time; enforced by
    the service, which also moves the occurrence's attendance).
    """

    original_date: date
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


class EffectiveClassInstanceResponse(BaseModel):
    """One effective dated class occurrence for the schedule board.

    Produced by the expander (recurrence + exceptions applied,
    ``include_cancelled=True``) and enriched from the class row, the gym's
    employees, and the attendance log.

    Attributes:
        class_id: The owning class.
        gym_id: The owning gym.
        class_name: The class's display name.
        class_date: The effective (post-reschedule) local date.
        occurred_at: UTC, timezone-aware start instant.
        resolved_class_time: Effective local start time (override or default).
        resolved_duration_minutes: Effective length (override or default).
        resolved_instructor_id: Effective instructor (override or weekday
            default); None when no instructor is assigned.
        resolved_instructor_name: ``first_name last_name`` for the resolved
            instructor (None when unassigned or not found).
        image_url: The class image, if any.
        points_worth: Points awarded for attending.
        max_capacity: Class capacity (None = unlimited).
        is_cancelled: True when this occurrence is cancelled (still shown).
        has_instance_exception: True when an instance exception exists on this
            occurrence's original date.
        has_range_exception: True when a range exception covers this
            occurrence's original date.
        attendance_count: Recorded attendance for this occurrence when a
            ``class_history`` row exists for it; None when no history row has
            been materialized yet.
        signup_count: Members signed up (reserved) for this occurrence — 0
            when none. Shown for both future AND past occurrences (a sign-up
            can be created ahead of a class that hasn't run yet, and the past
            count is a record of how many reserved a class that already ran).
    """

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_date: date
    occurred_at: datetime
    resolved_class_time: time
    resolved_duration_minutes: int
    resolved_instructor_id: UUID | None
    resolved_instructor_name: str | None
    image_url: str | None
    points_worth: int
    max_capacity: int | None
    is_cancelled: bool
    has_instance_exception: bool
    has_range_exception: bool
    attendance_count: int | None
    signup_count: int = 0


class EffectiveClassInstanceListResponse(BaseModel):
    """The schedule-board feed: effective occurrences across a date window."""

    items: list[EffectiveClassInstanceResponse]
