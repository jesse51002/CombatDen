from datetime import datetime
from enum import StrEnum
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
    stripe_invoice_id: str | None = None
    stripe_payment_intent_id: str | None = None
    invoice_time: datetime | None = None
    stripe_event_payload: dict | None = None
