from enum import StrEnum
from uuid import UUID

from . import SeedModel


class EmployeeType(StrEnum):
    """Gym employee role type."""

    owner = "owner"
    admin = "admin"
    trainer = "trainer"


class ThemeMode(StrEnum):
    """CRM admin-app appearance preference. 'system' follows the OS."""

    system = "system"
    light = "light"
    dark = "dark"


class GymEmployeeCreate(SeedModel):
    employee_id: UUID
    user_id: UUID | None = None
    gym_id: UUID
    employee_type: EmployeeType
    first_name: str
    last_name: str
    phone: str | None = None
    email: str | None = None
    employee_pic_url: str | None = None
    employee_public_description: str | None = None
    theme_preference: ThemeMode = ThemeMode.system
