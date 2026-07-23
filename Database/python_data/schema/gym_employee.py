from enum import StrEnum
from uuid import UUID

from pydantic import field_validator

from . import SeedModel


class EmployeeType(StrEnum):
    """Gym employee role type."""

    owner = "owner"
    admin = "admin"
    trainer = "trainer"
    front_desk = "front_desk"


class ThemeMode(StrEnum):
    """CRM admin-app appearance preference. 'system' follows the OS."""

    system = "system"
    light = "light"
    dark = "dark"


class GymEmployeeCreate(SeedModel):
    employee_id: UUID
    gym_id: UUID
    employee_type: EmployeeType
    first_name: str
    last_name: str
    phone: str | None = None
    email: str | None = None
    employee_pic_url: str | None = None
    employee_public_description: str | None = None
    theme_preference: ThemeMode = ThemeMode.system

    @field_validator("email")
    @classmethod
    def _lowercase_email(cls, v: str | None) -> str | None:
        """There is no more user_id FK — a verified Supabase auth account
        whose email matches THIS column (compared lowercase) is this
        person's access. Normalize to lowercase so a seeded row always
        matches the auth account created for it."""
        return v.lower() if v is not None else v
