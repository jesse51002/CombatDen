from datetime import datetime
from typing import Optional
from uuid import UUID

from . import SeedModel


class UserGymTransactionCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    item_id: UUID
    amount_paid: float
    item_type: Optional[str] = None
    time: Optional[datetime] = None
    applied_discounts: Optional[list[dict]] = None
    extra_info: dict = {}
