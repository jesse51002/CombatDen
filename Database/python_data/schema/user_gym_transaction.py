from datetime import datetime
from enum import StrEnum
from typing import Optional
from uuid import UUID

from . import SeedModel


class TransactionItemType(StrEnum):
    """Known transaction item types."""

    membership_payment = "membership_payment"
    reward_purchase = "reward_purchase"
    merchandise = "merchandise"


class UserGymTransactionCreate(SeedModel):
    crm_user_id: UUID
    gym_id: UUID
    item_id: UUID
    amount_paid: float
    item_type: Optional[TransactionItemType] = None
    time: Optional[datetime] = None
    applied_discounts: Optional[list[dict]] = None
    stripe_payment_intent_id: Optional[str] = None
    stripe_invoice_id: Optional[str] = None
    extra_info: dict = {}
