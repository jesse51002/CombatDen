from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import field_validator

from . import SeedModel


class UserGymProfileCreate(SeedModel):
    crm_user_id: UUID
    user_id: Optional[UUID] = None
    gym_id: UUID
    last_class: Optional[datetime] = None
    first_name: str
    last_name: str
    photo_url: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    emergency_contact_email: Optional[str] = None
    current_rank: Optional[int] = None
    points_balance: int = 0

    @field_validator("current_rank")
    @classmethod
    def rank_in_range(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and not 1 <= v <= 5:
            raise ValueError("current_rank must be between 1 and 5")
        return v
