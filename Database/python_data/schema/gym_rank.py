from enum import StrEnum
from uuid import UUID

from . import SeedModel


class GymType(StrEnum):
    """Mirrors the Postgres `gym_type` enum in rank_presets.sql."""

    bjj = "bjj"
    mma = "mma"
    generic = "generic"


class RankPresetCreate(SeedModel):
    preset_id: UUID
    gym_type: GymType
    main_rank_num_order: int
    sub_rank_num_order: int
    main_name: str
    sub_name: str
    classes_till_rankup: int
    image_url: str | None = None
    color: str | None = None


class GymRankCreate(SeedModel):
    rank_id: UUID
    gym_id: UUID
    main_rank_num_order: int
    sub_rank_num_order: int
    main_name: str
    sub_name: str
    classes_till_rankup: int
    image_url: str | None = None
    color: str | None = None
