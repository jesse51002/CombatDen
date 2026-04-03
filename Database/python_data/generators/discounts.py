import random
import uuid
from datetime import date, timedelta

from schema.gym_discount import GymDiscountCreate

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
            ["membership", "custom"], weights=[75, 25]
        )[0]
        discounts.append(
            GymDiscountCreate(
                discount_id=uuid.uuid4(),
                gym_id=gym_id,
                discount_name=name,
                discount_type=discount_type,
                discount_active=random.random() > 0.15,
                percentage_off=round(random.uniform(5, 25), 1) if use_pct else None,
                dollar_off=round(random.uniform(5, 50), 2) if not use_pct else None,
                end_date=date.today() + timedelta(days=random.randint(30, 180)),
            )
        )
    return discounts
