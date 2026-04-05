from enum import StrEnum
from typing import Optional
from uuid import UUID

from . import SeedModel


class EmployeeType(StrEnum):
    """Gym employee role type."""

    owner = "owner"
    admin = "admin"
    trainer = "trainer"


class GymEmployeeCreate(SeedModel):
    employee_id: UUID
    user_id: Optional[UUID] = None
    gym_id: UUID
    employee_type: EmployeeType
    first_name: str
    last_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    employee_pic_url: Optional[str] = None
    employee_public_description: Optional[str] = None
