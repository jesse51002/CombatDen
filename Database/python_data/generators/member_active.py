"""Generate member_active periods.

Each seeded member gets a single open-ended current period: ~70%
active, ~30% inactive. start_date is in the recent past. The gist
EXCLUDE on the table forbids overlap so we keep it to one row per
member.
"""

from __future__ import annotations

import random
import uuid

from generators.members import MemberPlan
from schema.member_active import MemberActiveCreate, MemberActiveType
from utils import today_offset

ACTIVE_RATIO = 0.7


def generate(gym_id: uuid.UUID, plans: list[MemberPlan]) -> list[MemberActiveCreate]:
    rows: list[MemberActiveCreate] = []
    for plan in plans:
        active_type = (
            MemberActiveType.active
            if random.random() < ACTIVE_RATIO
            else MemberActiveType.inactive
        )
        start = today_offset(-random.randint(14, 180))
        rows.append(
            MemberActiveCreate(
                active_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                active_type=active_type,
                start_date=start,
                end_date=None,
            )
        )
    return rows
