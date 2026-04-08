import random
import uuid

from schema.gym_discount import GymDiscountCreate
from schema.membership_plan import MembershipPlanCreate

DISCOUNT_NAMES = [
    "Military Discount", "Student Discount", "Early Bird",
    "Senior Discount", "Family Bundle", "Referral Bonus",
]


def generate(gym_id: uuid.UUID, count: int) -> list[GymDiscountCreate]:
    names = random.sample(DISCOUNT_NAMES, min(count, len(DISCOUNT_NAMES)))
    discounts = []
    for name in names:
        use_pct = random.choice([True, False])
        discount_type = random.choices(
            ["preset", "custom"], weights=[75, 25]
        )[0]
        duration = random.choice(["once", "repeating", "forever"])
        discounts.append(
            GymDiscountCreate(
                discount_id=uuid.uuid4(),
                gym_id=gym_id,
                discount_name=name,
                discount_type=discount_type,
                percentage_off=round(random.uniform(5, 25), 1) if use_pct else None,
                dollar_off=random.randint(500, 5000) if not use_pct else None,
                duration=duration,
                duration_in_months=random.randint(1, 12) if duration == "repeating" else None,
            )
        )
    return discounts


def generate_linked_discounts(
    gym_id: uuid.UUID, plans: list[MembershipPlanCreate]
) -> list[GymDiscountCreate]:
    """Generate linked discounts for recurring plans (1-3 tiers per plan)."""
    recurring_plans = [p for p in plans if p.plan_type == "recurring"]
    linked_discounts = []
    for plan in recurring_plans:
        num_tiers = random.randint(1, 3)
        base_pct = random.uniform(5, 15)
        for i in range(1, num_tiers + 1):
            pct = round(base_pct + (i - 1) * 5, 1)
            linked_discounts.append(
                GymDiscountCreate(
                    discount_id=uuid.uuid4(),
                    gym_id=gym_id,
                    discount_name=f"{plan.plan_name} - Linked Member #{i}",
                    discount_type="linked",
                    percentage_off=pct,
                    membership_plan_id=plan.plan_id,
                    linked_discount_num=i,
                    duration="forever",
                )
            )
    return linked_discounts
