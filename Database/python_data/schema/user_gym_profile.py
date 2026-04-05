from datetime import datetime
from typing import Optional
from uuid import UUID

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
    points_balance: int = 0
    streak: int = 0
    account_linked_to_id: Optional[UUID] = None
