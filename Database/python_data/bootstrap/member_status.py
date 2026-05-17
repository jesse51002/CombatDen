"""Direct-DB seeding for member_status periods."""

from __future__ import annotations

import uuid

from generators import member_status as member_status_generator
from generators.members import MemberPlan
from supabase import Client


def create(client: Client, gym_id: uuid.UUID, plans: list[MemberPlan]) -> int:
    rows = member_status_generator.generate(gym_id, plans)
    if rows:
        batch_size = 500
        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            client.table("member_status").insert(
                [r.to_insert_dict() for r in batch]
            ).execute()
    return len(rows)
