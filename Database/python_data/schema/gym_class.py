from datetime import date, datetime, time
from uuid import UUID

from . import SeedModel


class GymClassCreate(SeedModel):
    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: str | None = None
    allowed_plan_ids: list[UUID] | None = None
    max_capacity: int | None = None
    is_active: bool = True
    is_deleted: bool = False


class GymClassScheduleCreate(SeedModel):
    schedule_id: UUID
    class_id: UUID
    gym_id: UUID
    class_time: time
    duration_minutes: int
    recurring_unit: str
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
    is_cancelled: bool = False
    start_date: date
    end_date: date | None = None


class GymClassExceptionCreate(SeedModel):
    exception_id: UUID
    schedule_id: UUID
    gym_id: UUID
    original_date: date
    is_cancelled: bool | None = None
    new_class_time: time | None = None
    new_duration_minutes: int | None = None
    new_max_capacity: int | None = None
    new_instructor_id: UUID | None = None


class GymClassLogCreate(SeedModel):
    log_id: UUID
    crm_user_id: UUID
    gym_id: UUID
    class_id: UUID
    plan_id: UUID
    item_id: UUID
    instructor_id: UUID | None = None
    time: datetime | None = None
