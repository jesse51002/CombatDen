"""Direct-DB seeding for rank_presets and per-gym gym_ranks."""

from __future__ import annotations

import uuid

from generators import ranks as ranks_generator
from schema.gym_rank import GymRankCreate, GymType
from supabase import Client


def create_presets(client: Client) -> None:
    """Insert all rank_presets rows. Upsert-friendly on the
    (gym_type, main_rank_num_order, sub_rank_num_order) UNIQUE so re-runs
    don't duplicate."""
    presets = ranks_generator.build_presets()
    client.table("rank_presets").upsert(
        [p.to_insert_dict() for p in presets],
        on_conflict="gym_type,main_rank_num_order,sub_rank_num_order",
    ).execute()
    print(f"  rank_presets: {len(presets)} rows")


def create_gym_ranks(
    client: Client,
    gym_id: uuid.UUID,
    gym_type: GymType,
) -> list[GymRankCreate]:
    """Clone the preset ladder for `gym_type` into gym_ranks for one gym."""
    ranks = ranks_generator.clone_preset_for_gym(gym_id, gym_type)
    client.table("gym_ranks").insert([r.to_insert_dict() for r in ranks]).execute()
    return ranks
