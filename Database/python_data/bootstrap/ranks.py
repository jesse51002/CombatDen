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
    the gym's `sub_rank_type` when the kind implies one.

    `GymCreate` carries no sub_rank_type field (the column defaults to 'stripes'
    in the DB), so a stripes/div preset sets it here via a targeted service-role
    UPDATE on the gyms row. Returns the cloned rows plus the effective
    sub_rank_type (the implied type, or the 'stripes' default) so callers can
    label leaves without re-reading the gym.
    """
    ranks = ranks_generator.clone_preset_for_gym(gym_id, kind)
    client.table("gym_ranks").insert([r.to_insert_dict() for r in ranks]).execute()

    implied = ranks_generator.implied_sub_rank_type(kind)
    if implied is not None:
        client.table("gyms").update({"sub_rank_type": implied.value}).eq(
            "gym_id", str(gym_id)
        ).execute()

    return ranks, implied or SubRankType.stripes
