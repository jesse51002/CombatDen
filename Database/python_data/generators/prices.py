import uuid

from schema.membership_plan_price import MembershipPlanPriceCreate


def generate(
    plan_id: uuid.UUID, gym_id: uuid.UUID, price_amount: int
) -> MembershipPlanPriceCreate:
    """Create one active price for a plan."""
    return MembershipPlanPriceCreate(
        price_id=uuid.uuid4(),
        plan_id=plan_id,
        gym_id=gym_id,
        price=price_amount,
        is_active=True,
    )
