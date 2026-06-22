from datetime import datetime
from enum import StrEnum
from uuid import UUID

from . import SeedModel


class ChargeKind(StrEnum):
    payment = "payment"
    refund = "refund"


class ChargeStatus(StrEnum):
    pending = "pending"
    succeeded = "succeeded"
    failed = "failed"


class MemberChargeCreate(SeedModel):
    charge_id: UUID
    invoice_id: UUID
    gym_id: UUID
    # The payer (mirrors the invoice's paid_by_member_id); the beneficiary
    # set lives on the invoice (paid_for), not here.
    paid_by_member_id: UUID
    kind: ChargeKind
    status: ChargeStatus
    amount: int  # signed: payment >= 0, refund <= 0
    currency: str = "usd"
    payment_method_type: str | None = None
    card_last_four: str | None = None
    stripe_charge_id: str | None = None
    stripe_refund_id: str | None = None
    refunds_charge_id: UUID | None = None
    charge_time: datetime | None = None
    stripe_event_payload: dict | None = None
