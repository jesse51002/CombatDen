import random
import uuid
from datetime import date, timedelta

from schema.gym_history import GymHistoryCreate


def generate(
    gym_id: uuid.UUID, member_count: int, days: int
) -> list[GymHistoryCreate]:
    rows = []
    total = member_count
    for i in range(days):
        d = date.today() - timedelta(days=days - i)
        gained = random.randint(0, 3)
        churned = random.randint(0, 2)
        total = max(0, total + gained - churned)
        retained = max(0, total - churned)
        avg_revenue_per_member = random.uniform(40, 80)
        rows.append(
            GymHistoryCreate(
                gym_id=gym_id,
                date=d,
                members_total=total,
                members_gained=gained,
                members_churned=churned,
                members_retained=retained,
                revenue=round(total * avg_revenue_per_member, 2),
            )
        )
    return rows
