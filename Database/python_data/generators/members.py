"""In-memory member builder. Account status (trial / full / disabled,
plus the implicit "inactive" when no row covers today) lives in
member_status, not on members. See generators/member_status.py.
"""

from __future__ import annotations

import random
import uuid
from dataclasses import dataclass

from constants import MEMBERS_PER_GYM
from faker import Faker
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate

fake = Faker()


@dataclass
class MemberPlan:
    member_id: uuid.UUID
    first_name: str
    last_name: str
    email: str
    points_balance: int
    current_rank_id: uuid.UUID | None
    # Lifecycle archetype, used downstream to seed member_status periods.
    # One of: 'in_trial', 'churned_trial', 'converted_full',
    # 'converted_then_churned', 'full_then_disabled', 'never_started'.
    lifecycle: str


def _pick_rank_id(ranks: list[GymRankCreate]) -> uuid.UUID | None:
    if not ranks:
        return None
    sorted_ranks = sorted(
        ranks, key=lambda r: (r.main_rank_num_order, r.sub_rank_num_order)
    )
    idx = int(random.triangular(0, len(sorted_ranks) - 1, 0))
    return sorted_ranks[idx].rank_id


def _pick_lifecycle() -> str:
    roll = random.random()
    if roll < 0.20:
        return "in_trial"
    if roll < 0.30:
        return "churned_trial"
    if roll < 0.77:
        return "converted_full"
    if roll < 0.87:
        return "converted_then_churned"
    if roll < 0.90:
        return "full_then_disabled"
    return "never_started"


def build_plans(ranks: list[GymRankCreate]) -> list[MemberPlan]:
    plans: list[MemberPlan] = []
    for _ in range(MEMBERS_PER_GYM):
        plans.append(
            MemberPlan(
                member_id=uuid.uuid4(),
                first_name=fake.first_name(),
                last_name=fake.last_name(),
                email=fake.unique.email(),
                points_balance=random.randint(0, 500),
                current_rank_id=_pick_rank_id(ranks),
                lifecycle=_pick_lifecycle(),
            )
        )
    return plans


def to_create(gym_id: uuid.UUID, plan: MemberPlan) -> MemberCreate:
    return MemberCreate(
        member_id=plan.member_id,
        gym_id=gym_id,
        first_name=plan.first_name,
        last_name=plan.last_name,
        email=plan.email,
        points_balance=plan.points_balance,
        current_rank_id=plan.current_rank_id,
    )
