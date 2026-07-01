from datetime import date, datetime, time
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class RecurringUnit(StrEnum):
    """Mirrors the Postgres `recurring_unit` enum in gym_class_schedules.sql."""

    daily = "daily"
    weekly = "weekly"
    monthly = "monthly"


class GymClassCreate(SeedModel):
    """Class IDENTITY only — the schedule shape lives on the versioned
    GymClassScheduleCreate rows (gym_class_schedules)."""

    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: str | None = None
    # JSONB array of plan_id strings allowed to attend; None = all plans.
    allowed_plan_ids: list[UUID] | None = None
    max_capacity: int | None = None
    image_url: str | None = None
    points_worth: int = 50
    is_active: bool = True
    is_deleted: bool = False


class GymClassScheduleCreate(SeedModel):
    """One append-only schedule VERSION of a class (gym_class_schedules).

    A version owns the occurrences whose original instant (original_date +
    class_time in the version's own frozen timezone) falls inside
    [effective_from, next version's effective_from).
    """

    schedule_id: UUID
    class_id: UUID
    gym_id: UUID
    effective_from: datetime
    # IANA zone frozen at mint (copied from gyms.timezone).
    timezone: str
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
    # Reschedule target (any date); None = not rescheduled.
    new_date: date | None = None


class ClassRangeExceptionCreate(SeedModel):
    """Cancel or change instructor across a continuous date range."""

    exception_id: UUID
    class_id: UUID
    gym_id: UUID
    start_date: date
    end_date: date
    is_cancelled: bool = False
    new_instructor_id: UUID | None = None


class MemberAttendanceCreate(SeedModel):
    """A member's attendance at a class occurrence.

    Keyed by the occurrence's ORIGINAL slot (class_id + original_date +
    original_time — the owning schedule version's slot before exceptions).
    occurred_at is the denormalized EFFECTIVE start instant. Attributed to
    the membership row (item_id) + plan that covered the check-in, mirroring
    the gated check-in flow; both None for a no-membership admin check-in.
    """

    log_id: UUID
    member_id: UUID
    gym_id: UUID
    class_id: UUID
    original_date: date
    original_time: time
    occurred_at: datetime
    plan_id: UUID | None = None
    item_id: UUID | None = None


class ClassSignupCreate(SeedModel):
    """A member's reservation for a class occurrence (not attendance).

    Keyed by the occurrence's ORIGINAL slot, exactly like attendance. Seeded
    by `generators.classes.generate_class_signups` for both past occurrences
    (mixed with the already-seeded attendance, for a signed-up-and-attended /
    no-show / walk-in mix) and future occurrences (sign-ups only -- a future
    occurrence has no attendance yet).
    """

    signup_id: UUID
    gym_id: UUID
    class_id: UUID
    member_id: UUID
    original_date: date
    original_time: time
