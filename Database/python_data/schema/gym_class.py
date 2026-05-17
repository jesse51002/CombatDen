from datetime import date, datetime, time
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class RecurringUnit(StrEnum):
    """Mirrors the Postgres `recurring_unit` enum in gym_classes.sql."""

    daily = "daily"
    weekly = "weekly"
    monthly = "monthly"


class GymClassCreate(SeedModel):
    """Gym class with embedded recurring schedule (one root schedule per class)."""

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: str | None = None
    max_capacity: int | None = None
    is_active: bool = True
    is_deleted: bool = False
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


class ClassInstanceExceptionCreate(SeedModel):
    """Override for a single occurrence on a specific date."""

    exception_id: UUID
    class_id: UUID
    gym_id: UUID
    original_date: date
    is_cancelled: bool = False
    new_class_time: time | None = None
    new_duration_minutes: int | None = None
    new_max_capacity: int | None = None
    new_instructor_id: UUID | None = None


class ClassRangeExceptionCreate(SeedModel):
    """Cancel or change instructor across a continuous date range."""

    exception_id: UUID
    class_id: UUID
    gym_id: UUID
    start_date: date
    end_date: date
    is_cancelled: bool = False
    new_instructor_id: UUID | None = None


class ClassHistoryCreate(SeedModel):
    """One row per class instance that actually occurred."""

    class_history_id: UUID
    class_id: UUID
    gym_id: UUID
    instructor_id: UUID | None = None
    occurred_at: datetime
    duration_minutes: int


class MemberAttendanceCreate(SeedModel):
    """A member's attendance at a specific class instance (class_history row)."""

    log_id: UUID
    member_id: UUID
    gym_id: UUID
    class_history_id: UUID
