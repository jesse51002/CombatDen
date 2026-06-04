from uuid import UUID

from . import SeedModel


class MembershipPlanPriceCreate(SeedModel):
    price_id: UUID
    plan_id: UUID
    gym_id: UUID
    stripe_price_id: str | None = None
    price: int
    is_active: bool = True
