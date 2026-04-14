from datetime import datetime
from enum import StrEnum
from typing import Optional
from uuid import UUID

from . import SeedModel


class InvoiceStatus(StrEnum):
    open = "open"
    paid = "paid"


class UserGymInvoiceCreate(SeedModel):
    invoice_id: UUID
    gym_id: UUID
    crm_user_id: UUID
    status: InvoiceStatus = InvoiceStatus.open
    total_amount: int
    currency: str = "usd"
    stripe_invoice_id: Optional[str] = None
    stripe_payment_intent_id: Optional[str] = None
    invoice_time: Optional[datetime] = None
    stripe_event_payload: Optional[dict] = None
