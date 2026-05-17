"""Direct-DB seeding for members.

Returns both the persisted MemberCreate rows and the in-memory plans so
member_status seeding downstream can read each member's chosen
lifecycle archetype.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from generators import members as members_generator
from generators.members import MemberPlan
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate
from supabase import Client


@dataclass
class MemberSeed:
    rows: list[MemberCreate]
    plans: list[MemberPlan]


def create(
    client: Client,
    gym_id: uuid.UUID,
    ranks: list[GymRankCreate],
) -> MemberSeed:
    plans = members_generator.build_plans(ranks)
    rows = [members_generator.to_create(gym_id, p) for p in plans]
    client.table("members").insert([r.to_insert_dict() for r in rows]).execute()
    return MemberSeed(rows=rows, plans=plans)
