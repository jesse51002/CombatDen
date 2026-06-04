from uuid import UUID

from . import SeedModel


class MemberInvoiceAppliedDiscountCreate(SeedModel):
    applied_discount_id: UUID
    invoice_id: UUID
    gym_id: UUID
    discount_id: UUID
    amount_off: int
    stripe_coupon_id: str | None = None
