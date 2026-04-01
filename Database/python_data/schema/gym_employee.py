from typing import Literal, Optional
from uuid import UUID

from . import SeedModel


class GymEmployeeCreate(SeedModel):
    employee_id: UUID
    user_id: Optional[UUID] = None
    gym_id: UUID
    employee_type: Literal["owner", "admin", "trainer"]
    first_name: str
    last_name: str
    phone: Optional[str] = None
    email: Optional[str] = None
