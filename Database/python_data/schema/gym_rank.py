from enum import StrEnum
from uuid import UUID

from pydantic import Field

from . import SeedModel


class GymType(StrEnum):
    """Discipline vocabulary used by the video / presets JSONB.

    No longer mirrors a Postgres enum — the old `gym_type` enum in
    rank_presets.sql was dropped when rank_presets was re-keyed to
    `rank_preset_kind`. This StrEnum survives purely as the discipline
    label set (bjj / mma / generic) that video and preset data key on.
    """

    bjj = "bjj"
    mma = "mma"
    generic = "generic"


class SubRankType(StrEnum):
    """Mirrors the Postgres `sub_rank_type` enum in gyms.sql.

    `none` (the DB default) means the gym has main belts but NO sub-positions
    — every rank behaves as its own leaf (effective sub_rank_count 0) and
    members carry a NULL current_sub_index. `stripes` / `div` only change the
    LABEL of the sub-positions; the type is a per-gym view state layered over
    each rank's persisted sub_rank_count, never a destructive wipe.
    """

    none = "none"
    stripes = "stripes"
    div = "div"


class RankPresetKind(StrEnum):
    """Mirrors the Postgres `rank_preset_kind` enum in rank_presets.sql."""

    bjj_belts = "bjj_belts"
    bjj_belts_stripes = "bjj_belts_stripes"
    flat = "flat"


def sub_rank_label(sub_rank_type: SubRankType, sub_index: int | None) -> str | None:
    """Derived sub-rank label. `none`: always None (the gym has no sub-ranks).
    stripes: 0 -> None (bare belt), 1 -> '1 Stripe', k -> 'k Stripes'. div:
    i -> 'Div {i+1}'. None when sub_index is None.

    A `none` gym never has a real sub-position (its members carry NULL
    current_sub_index), so this returns None regardless of `sub_index` —
    guarding against a stray index producing a phantom label."""
    if sub_rank_type is SubRankType.none or sub_index is None:
        return None
    if sub_rank_type is SubRankType.stripes:
        if sub_index == 0:
            return None
        return "1 Stripe" if sub_index == 1 else f"{sub_index} Stripes"
    return f"Div {sub_index + 1}"


def rank_display_name(name: str, sub_rank_type: SubRankType, sub_index: int | None) -> str:
    """'Main' when leaf/base, else 'Main · SubLabel'."""
    label = sub_rank_label(sub_rank_type, sub_index)
    return name if label is None else f"{name} · {label}"


class RankPresetCreate(SeedModel):
    preset_id: UUID
    preset_kind: RankPresetKind
    main_rank_num_order: int
    name: str
    image_url: str | None = None
    classes_to_next_major: int
    sub_rank_count: int = 0
    implied_sub_rank_type: SubRankType | None = None


class GymRankCreate(SeedModel):
    rank_id: UUID
    gym_id: UUID
    main_rank_num_order: int
    name: str
    image_url: str | None = None
    classes_to_next_major: int
    sub_rank_count: int = 0
    sub_rank_image_overrides: dict = Field(default_factory=dict)
