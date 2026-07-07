"""Rank preset ladders + clone helper (two-level model).

`build_presets()` returns the canonical MAIN-rank rows for every
`RankPresetKind` (one row per main rank; sub-ranks are a per-row count, not
their own rows). `clone_preset_for_gym()` copies one kind's rows into
`gym_ranks` rows for a specific gym. `implied_sub_rank_type()` exposes the
per-gym `sub_rank_type` a kind implies (so the bootstrap can stamp the gym).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from schema.gym_rank import (
    GymRankCreate,
    RankPresetCreate,
    RankPresetKind,
    SubRankType,
)

# placeholder belt art; the founder uploads the real PNGs to
# s3://combatden-assets/rank/presets/{white,blue}.png (CDN cdn.combatden.net);
# alternating white/blue until real art is supplied.
_BELT_IMG_EVEN = "https://cdn.combatden.net/rank/presets/white.png"
_BELT_IMG_ODD = "https://cdn.combatden.net/rank/presets/blue.png"


@dataclass(frozen=True)
class _PresetRow:
    main_rank_num_order: int
    name: str
    classes_to_next_major: int
    sub_rank_count: int
    image_url: str | None = None


# BJJ: 5 belts White -> Black (order 0..4). classes_to_next_major is the count
# to the next MAJOR belt (the top belt is already at the top, so 0). The plain
# `bjj_belts` kind carries no sub-ranks; `bjj_belts_stripes` reuses the SAME
# belts with sub_rank_count = 5 (base + 4 stripes) and the stripes sub type.
_BJJ_BELT_NAMES = ["White Belt", "Blue Belt", "Purple Belt", "Brown Belt", "Black Belt"]
_BJJ_THRESHOLDS = [100, 150, 200, 250, 0]


def _belt_image(idx: int) -> str:
    """Alternating placeholder belt art (even -> white, odd -> blue)."""
    return _BELT_IMG_EVEN if idx % 2 == 0 else _BELT_IMG_ODD


def _bjj_rows(sub_rank_count: int) -> list[_PresetRow]:
    return [
        _PresetRow(
            main_rank_num_order=i,
            name=name,
            classes_to_next_major=_BJJ_THRESHOLDS[i],
            sub_rank_count=sub_rank_count,
            image_url=_belt_image(i),
        )
        for i, name in enumerate(_BJJ_BELT_NAMES)
    ]


# Flat: 5 skill tiers Beginner -> Elite (order 0..4), no sub-ranks. Left without
# preset art (placeholder belt PNGs are BJJ-specific); a gym uploads its own on
# the edit page. Switch to `_belt_image(i)` here if generic tier art is added.
_FLAT_NAMES = ["Beginner", "Novice", "Intermediate", "Advanced", "Elite"]
_FLAT_THRESHOLDS = [20, 30, 50, 80, 0]


def _flat_rows() -> list[_PresetRow]:
    return [
        _PresetRow(
            main_rank_num_order=i,
            name=name,
            classes_to_next_major=_FLAT_THRESHOLDS[i],
            sub_rank_count=0,
            image_url=None,
        )
        for i, name in enumerate(_FLAT_NAMES)
    ]


_KIND_ROWS: dict[RankPresetKind, list[_PresetRow]] = {
    RankPresetKind.bjj_belts: _bjj_rows(sub_rank_count=0),
    RankPresetKind.bjj_belts_stripes: _bjj_rows(sub_rank_count=5),
    RankPresetKind.flat: _flat_rows(),
}

# The per-gym sub_rank_type a kind implies. Every kind implies a CONCRETE
# gym-level style now: the plain-belt and flat kinds imply 'none' (main belts,
# no sub-positions), only the stripes kind implies 'stripes'. from_preset
# stamps this value onto the gym directly.
_IMPLIED_SUB_TYPE: dict[RankPresetKind, SubRankType] = {
    RankPresetKind.bjj_belts: SubRankType.none,
    RankPresetKind.bjj_belts_stripes: SubRankType.stripes,
    RankPresetKind.flat: SubRankType.none,
}


def implied_sub_rank_type(kind: RankPresetKind) -> SubRankType:
    """The `sub_rank_type` this kind stamps onto a gym (always concrete —
    'none' for plain belts / flat, 'stripes' for the stripes kind)."""
    return _IMPLIED_SUB_TYPE[kind]


def build_presets() -> list[RankPresetCreate]:
    """Every rank_presets row across all three kinds (one row per main rank)."""
    presets: list[RankPresetCreate] = []
    for kind, rows in _KIND_ROWS.items():
        implied = _IMPLIED_SUB_TYPE[kind]
        for row in rows:
            presets.append(
                RankPresetCreate(
                    preset_id=uuid.uuid4(),
                    preset_kind=kind,
                    main_rank_num_order=row.main_rank_num_order,
                    name=row.name,
                    image_url=row.image_url,
                    classes_to_next_major=row.classes_to_next_major,
                    sub_rank_count=row.sub_rank_count,
                    implied_sub_rank_type=implied,
                )
            )
    return presets


def clone_preset_for_gym(gym_id: uuid.UUID, kind: RankPresetKind) -> list[GymRankCreate]:
    """Clone one kind's main-rank rows into gym_ranks rows for one gym.

    `sub_rank_image_overrides` starts empty ({}) — the effective sub image is
    the main row's image until the gym writes an override on the edit page.
    """
    return [
        GymRankCreate(
            rank_id=uuid.uuid4(),
            gym_id=gym_id,
            main_rank_num_order=row.main_rank_num_order,
            name=row.name,
            image_url=row.image_url,
            classes_to_next_major=row.classes_to_next_major,
            sub_rank_count=row.sub_rank_count,
            sub_rank_image_overrides={},
        )
        for row in _KIND_ROWS[kind]
    ]
