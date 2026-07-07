"""Direct-DB seeding for rank_presets and per-gym gym_ranks."""

from __future__ import annotations

import uuid

from generators import ranks as ranks_generator
from schema.gym_rank import GymRankCreate, RankPresetKind, SubRankType
from supabase import Client


def create_presets(client: Client) -> None:
    """Insert all rank_presets rows (one per main rank, across all three kinds).

    Upsert-friendly on the (preset_kind, main_rank_num_order) UNIQUE so re-runs
    don't duplicate."""
    presets = ranks_generator.build_presets()
    client.table("rank_presets").upsert(
        [p.to_insert_dict() for p in presets],
        on_conflict="preset_kind,main_rank_num_order",
    ).execute()
    print(f"  rank_presets: {len(presets)} rows")


def create_gym_ranks(
    client: Client,
    gym_id: uuid.UUID,
    kind: RankPresetKind,
) -> tuple[list[GymRankCreate], SubRankType]:
    """Clone the preset ladder for `kind` into gym_ranks for one gym, and stamp
    the gym's `sub_rank_type` with the style the kind implies.

    `GymCreate` carries no sub_rank_type field (the column defaults to 'none'
    in the DB), so this sets the implied style here via a targeted service-role
    UPDATE on the gyms row. Every kind implies a concrete style now — 'none'
    for plain belts / flat, 'stripes' for the stripes kind — so the update is
    unconditional. Returns the cloned rows plus that effective sub_rank_type so
    callers can label leaves without re-reading the gym.
    """
    ranks = ranks_generator.clone_preset_for_gym(gym_id, kind)
    client.table("gym_ranks").insert([r.to_insert_dict() for r in ranks]).execute()

    sub_rank_type = ranks_generator.implied_sub_rank_type(kind)
    client.table("gyms").update({"sub_rank_type": sub_rank_type.value}).eq(
        "gym_id", str(gym_id)
    ).execute()

    return ranks, sub_rank_type
