"""Pydantic models for the ranks domain."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field
from schema.gym_rank import GymType

HEX_COLOR_PATTERN = r"^#[0-9A-Fa-f]{6}$"


class RankSummary(BaseModel):
    """Nested rank object returned inside member responses."""

    rank_id: UUID
    main_name: str
    sub_name: str
    color: str | None
    image_url: str | None
    main_rank_num_order: int
    sub_rank_num_order: int


class RankResponse(RankSummary):
    """A single gym_ranks row."""

    gym_id: UUID
    classes_till_rankup: int
    created_at: datetime


class RankListResponse(BaseModel):
    """List of ranks for a gym."""

    items: list[RankResponse]


class RankCreateRequest(BaseModel):
    """Body for POST /api/v1/ranks/."""

    gym_id: UUID
    main_rank_num_order: int = Field(ge=0)
    sub_rank_num_order: int = Field(ge=0)
    main_name: str = Field(min_length=1)
    sub_name: str = Field(min_length=1)
    classes_till_rankup: int = Field(ge=0)
    image_url: str | None = None
    color: str | None = Field(default=None, pattern=HEX_COLOR_PATTERN)


class RankUpdateData(BaseModel):
    """Mutable fields on a gym_ranks row."""

    main_rank_num_order: int | None = Field(default=None, ge=0)
    sub_rank_num_order: int | None = Field(default=None, ge=0)
    main_name: str | None = Field(default=None, min_length=1)
    sub_name: str | None = Field(default=None, min_length=1)
    classes_till_rankup: int | None = Field(default=None, ge=0)
    image_url: str | None = None
    color: str | None = Field(default=None, pattern=HEX_COLOR_PATTERN)


class RankUpdateRequest(BaseModel):
    """Body for PUT /api/v1/ranks/{rank_id}."""

    data: RankUpdateData


class RankPresetResponse(BaseModel):
    """A single rank_presets row."""

    preset_id: UUID
    gym_type: GymType
    main_rank_num_order: int
    sub_rank_num_order: int
    main_name: str
    sub_name: str
    classes_till_rankup: int
    image_url: str | None
    color: str | None


class RankPresetListResponse(BaseModel):
    """Flat preset list for a single gym_type."""

    items: list[RankPresetResponse]


class SubRankPreset(BaseModel):
    """Leaf node — one sub-rank within a main-rank group."""

    preset_id: UUID
    sub_rank_num_order: int
    sub_name: str
    classes_till_rankup: int
    image_url: str | None
    color: str | None


class MainRankPresetGroup(BaseModel):
    """A main rank with its ordered list of sub-ranks."""

    main_rank_num_order: int
    main_name: str
    sub_ranks: list[SubRankPreset]


class AllPresetsGroupedResponse(BaseModel):
    """All preset ladders, keyed by gym_type, nested main → sub."""

    presets: dict[GymType, list[MainRankPresetGroup]]


class FromPresetRequest(BaseModel):
    """Body for POST /api/v1/ranks/from-preset."""

    gym_id: UUID
    gym_type: GymType


class RankEnabledRequest(BaseModel):
    """Body for PUT /api/v1/ranks/enabled."""

    gym_id: UUID
    is_rank_enabled: bool


class RankEnabledResponse(BaseModel):
    """Returns the gym's current rank-enabled state."""

    gym_id: UUID
    is_rank_enabled: bool


class RankMemberResponse(BaseModel):
    """Result of a manual member rank change (promote / set).

    ``new_rank`` is the member's rank after the change, or ``None``
    when the member was unassigned (set to no rank).
    """

    member_id: UUID
    new_rank: RankResponse | None = None


class RankPromoteMemberRequest(BaseModel):
    """Body for POST /api/v1/ranks/promote-member.

    Advances the member one step up the gym's ordered ladder. A
    rank-less member is assigned the lowest rank.
    """

    gym_id: UUID
    member_id: UUID


class RankSetMemberRequest(BaseModel):
    """Body for POST /api/v1/ranks/set-member-rank.

    Sets the member to an explicit rank (correction / demotion /
    assignment), or to no rank when ``rank_id`` is ``None``.
    """

    gym_id: UUID
    member_id: UUID
    rank_id: UUID | None = None


class RankReorderItem(BaseModel):
    """One rank's target position in a bulk reorder."""

    rank_id: UUID
    main_rank_num_order: int = Field(ge=0)
    sub_rank_num_order: int = Field(ge=0)


class RankReorderRequest(BaseModel):
    """Body for POST /api/v1/ranks/reorder.

    The full desired ordering for the affected ranks. Applied as a
    two-phase update so the unique-order constraint is never
    transiently violated.
    """

    gym_id: UUID
    ranks: list[RankReorderItem]
