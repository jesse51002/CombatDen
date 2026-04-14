from datetime import datetime
from enum import StrEnum
from typing import Optional
from uuid import UUID

from . import SeedModel


class ChargeKind(StrEnum):
    payment = "payment"
    refund = "refund"


class ChargeStatus(StrEnum):
    pending = "pending"
    succeeded = "succeeded"
    failed = "failed"


class UserGymChargeCreate(SeedModel):
    charge_id: UUID
    invoice_id: UUID
    gym_id: UUID
    crm_user_id: UUID
    kind: ChargeKind
    status: ChargeStatus
    amount: int  # signed: payment >= 0, refund <= 0
    currency: str = "usd"
    payment_method_type: Optional[str] = None
    stripe_charge_id: Optional[str] = None
    stripe_refund_id: Optional[str] = None
    refunds_charge_id: Optional[UUID] = None
    charge_time: Optional[datetime] = None
    stripe_event_payload: Optional[dict] = None
