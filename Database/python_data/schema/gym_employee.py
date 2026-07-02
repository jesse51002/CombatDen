from enum import StrEnum
from uuid import UUID

from pydantic import model_validator

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

    @model_validator(mode="after")
    def _trainer_has_no_account(self) -> "GymEmployeeCreate":
        """Mirrors chk_trainer_has_no_account: a trainer row is instructor
        DATA (name/photo on classes), never a login principal."""
        if (
            self.employee_type == EmployeeType.trainer
            and self.user_id is not None
        ):
            raise ValueError(
                "A trainer never carries a user_id — trainers have no "
                "accounts (they are instructor data, not principals)"
            )
        return self
