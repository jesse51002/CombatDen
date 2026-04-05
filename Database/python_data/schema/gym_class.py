from datetime import date, datetime, time
from typing import Optional
from uuid import UUID

from . import SeedModel


class GymClassCreate(SeedModel):
    class_id: UUID
    gym_id: UUID
    class_name: str
    class_description: Optional[str] = None
    allowed_plan_ids: Optional[list[UUID]] = None
    max_capacity: Optional[int] = None
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
    sun_instructor_id: Optional[UUID] = None
    mon_instructor_id: Optional[UUID] = None
    tue_instructor_id: Optional[UUID] = None
    wed_instructor_id: Optional[UUID] = None
    thu_instructor_id: Optional[UUID] = None
    fri_instructor_id: Optional[UUID] = None
    sat_instructor_id: Optional[UUID] = None
    is_cancelled: bool = False
    start_date: date
    end_date: Optional[date] = None


class GymClassExceptionCreate(SeedModel):
    exception_id: UUID
    schedule_id: UUID
    gym_id: UUID
    original_date: date
    is_cancelled: Optional[bool] = None
    new_class_time: Optional[time] = None
    new_duration_minutes: Optional[int] = None
    new_max_capacity: Optional[int] = None
    new_instructor_id: Optional[UUID] = None


class GymClassLogCreate(SeedModel):
    log_id: UUID
    crm_user_id: UUID
    gym_id: UUID
    class_id: UUID
    plan_id: UUID
    instructor_id: Optional[UUID] = None
    time: Optional[datetime] = None
