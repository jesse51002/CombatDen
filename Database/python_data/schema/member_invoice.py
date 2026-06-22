from datetime import datetime
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class InvoiceStatus(StrEnum):
    open = "open"
    paid = "paid"


class MemberInvoiceCreate(SeedModel):
    invoice_id: UUID
    gym_id: UUID
    # The payer (whose customer/card was billed) + the beneficiaries the
    # bill was FOR (usually just [payer]; a parent billing a child's
    # membership lists the child). There is no single conflated member_id.
    paid_by_member_id: UUID
    paid_for: list[UUID]
    status: InvoiceStatus = InvoiceStatus.open
    total_amount: int
    currency: str = "usd"
    stripe_invoice_id: str | None = None
    stripe_payment_intent_id: str | None = None
    invoice_time: datetime | None = None
    stripe_event_payload: dict | None = None
