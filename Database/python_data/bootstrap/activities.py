"""Direct-DB seeding for member_activities."""

from __future__ import annotations

import uuid

from constants import ACTIVITIES_PER_MEMBER
from generators import activities as activities_generator
from schema.member import MemberCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberCreate],
) -> None:
    for m in members:
        rows = activities_generator.generate(m.member_id, gym_id, ACTIVITIES_PER_MEMBER)
        client.table("member_activities").insert([r.to_insert_dict() for r in rows]).execute()
