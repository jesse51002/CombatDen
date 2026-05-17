import random
import uuid
from datetime import date, timedelta

from schema.gym_history import GymHistoryCreate


def generate(gym_id: uuid.UUID, member_count: int, days: int) -> list[GymHistoryCreate]:
    """Synthetic activity-state rollups: total_active / total_inactive
    balances plus daily transitions.
    """
    rows: list[GymHistoryCreate] = []
    total_active = max(1, int(member_count * 0.7))
    total_inactive = member_count - total_active
    for i in range(days):
        d = date.today() - timedelta(days=days - i)
        became = random.randint(0, 3)
        went = random.randint(0, 2)
        # Move members between buckets
        actual_became = min(became, total_inactive)
        actual_went = min(went, total_active)
        total_active = total_active + actual_became - actual_went
        total_inactive = total_inactive - actual_became + actual_went
        rows.append(
            GymHistoryCreate(
                gym_id=gym_id,
                date=d,
                total_active=total_active,
                total_inactive=total_inactive,
                went_inactive=actual_went,
                became_active=actual_became,
            )
        )
    return rows
