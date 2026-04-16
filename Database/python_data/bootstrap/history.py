"""Direct-DB seeding for gym_history analytics rollups."""

from __future__ import annotations

import uuid

from constants import HISTORY_DAYS
from generators import history as history_generator
from supabase import Client


def create(client: Client, gym_id: uuid.UUID, member_count: int) -> None:
    rows = history_generator.generate(gym_id, member_count, HISTORY_DAYS)
    client.table("gym_history").insert([h.to_insert_dict() for h in rows]).execute()
