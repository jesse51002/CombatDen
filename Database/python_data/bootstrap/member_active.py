"""Direct-DB seeding for member_active periods."""

from __future__ import annotations

import uuid

from generators import member_active as member_active_generator
from generators.members import MemberPlan
from supabase import Client


def create(client: Client, gym_id: uuid.UUID, plans: list[MemberPlan]) -> int:
    rows = member_active_generator.generate(gym_id, plans)
    if rows:
        batch_size = 500
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            client.table("member_active").insert(
                [r.to_insert_dict() for r in batch]
            ).execute()
    return len(rows)
