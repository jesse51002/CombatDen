from uuid import UUID

from . import SeedModel


class MemberInvoiceAppliedDiscountCreate(SeedModel):
    applied_discount_id: UUID
    invoice_id: UUID
    gym_id: UUID
    amount_off: int
    stripe_coupon_id: str
    discount_id: UUID | None = None
