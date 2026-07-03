"""Direct-DB seeding for member_activities."""

from __future__ import annotations

import uuid

from constants import ACTIVITIES_PER_MEMBER
from generators import activities as activities_generator
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberCreate],
    ranks: list[GymRankCreate],
) -> None:
    rank_names = {
        r.rank_id: f"{r.main_name} {r.sub_name}".strip() for r in ranks
    }
    for m in members:
        rows = activities_generator.generate(
            m.member_id,
            gym_id,
            ACTIVITIES_PER_MEMBER,
            current_rank_id=m.current_rank_id,
            current_rank_name=rank_names.get(m.current_rank_id),
        )
        client.table("member_activities").insert([r.to_insert_dict() for r in rows]).execute()
