"""Rank preset ladders + clone helper.

`build_presets()` returns the canonical rank rows for each gym_type.
`clone_preset_for_gym()` copies the rows for one gym_type into
gym_ranks rows for a specific gym.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from schema.gym_rank import GymRankCreate, GymType, RankPresetCreate


@dataclass(frozen=True)
class _PresetRow:
    main_rank_num_order: int
    sub_rank_num_order: int
    main_name: str
    sub_name: str
    classes_till_rankup: int
    color: str | None = None


# BJJ: 5 main belts × 5 stripes (0–4). Stripe 4 → next belt's stripe 0.
# Real-world progression varies wildly; these counts are illustrative.
_BJJ_BELTS = [
    ("White", "#FFFFFF"),
    ("Blue", "#1F6FEB"),
    ("Purple", "#8957E5"),
    ("Brown", "#8B4513"),
    ("Black", "#000000"),
]
_BJJ_STRIPE_GAPS = [15, 20, 25, 30, 60]  # classes between consecutive sub-ranks within a belt


def _bjj_rows() -> list[_PresetRow]:
    rows: list[_PresetRow] = []
    for belt_idx, (belt_name, belt_color) in enumerate(_BJJ_BELTS):
        for stripe in range(5):
            sub_name = f"{stripe} Stripes" if stripe != 1 else "1 Stripe"
            rows.append(
                _PresetRow(
                    main_rank_num_order=belt_idx,
                    sub_rank_num_order=stripe,
                    main_name=f"{belt_name} Belt",
                    sub_name=sub_name,
                    classes_till_rankup=_BJJ_STRIPE_GAPS[belt_idx],
                    color=belt_color,
                )
            )
    return rows


# MMA / generic: 5 flat skill tiers, sub_name == main_name (no sub-rank)
_TIERS = [
    ("Beginner", "#9CA3AF"),
    ("Novice", "#10B981"),
    ("Intermediate", "#3B82F6"),
    ("Advanced", "#8B5CF6"),
    ("Elite", "#F59E0B"),
]
_TIER_GAPS = [20, 30, 50, 80, 0]  # 0 on the top tier — already at the top


def _flat_rows() -> list[_PresetRow]:
    return [
        _PresetRow(
            main_rank_num_order=i,
            sub_rank_num_order=0,
            main_name=name,
            sub_name=name,
            classes_till_rankup=_TIER_GAPS[i],
            color=color,
        )
        for i, (name, color) in enumerate(_TIERS)
    ]


_PRESET_DATA: dict[GymType, list[_PresetRow]] = {
    GymType.bjj: _bjj_rows(),
    GymType.mma: _flat_rows(),
    GymType.generic: _flat_rows(),
}


def build_presets() -> list[RankPresetCreate]:
    presets: list[RankPresetCreate] = []
    for gym_type, rows in _PRESET_DATA.items():
        for row in rows:
            presets.append(
                RankPresetCreate(
                    preset_id=uuid.uuid4(),
                    gym_type=gym_type,
                    main_rank_num_order=row.main_rank_num_order,
                    sub_rank_num_order=row.sub_rank_num_order,
                    main_name=row.main_name,
                    sub_name=row.sub_name,
                    classes_till_rankup=row.classes_till_rankup,
                    color=row.color,
                )
            )
    return presets


def clone_preset_for_gym(gym_id: uuid.UUID, gym_type: GymType) -> list[GymRankCreate]:
    rows = _PRESET_DATA[gym_type]
    return [
        GymRankCreate(
            rank_id=uuid.uuid4(),
            gym_id=gym_id,
            main_rank_num_order=row.main_rank_num_order,
            sub_rank_num_order=row.sub_rank_num_order,
            main_name=row.main_name,
            sub_name=row.sub_name,
            classes_till_rankup=row.classes_till_rankup,
            color=row.color,
        )
        for row in rows
    ]
