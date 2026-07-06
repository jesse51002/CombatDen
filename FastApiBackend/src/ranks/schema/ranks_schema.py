"""Pydantic models for the ranks domain.

Two-level rank model: ``gym_ranks`` holds ONE row per MAIN rank; a member
is pinned to a leaf via ``current_rank_id`` + ``current_sub_index``. The
gym's ``sub_rank_type`` (stripes | div) + the index derive every sub-rank
LABEL — labels are never stored (see ``schema.gym_rank`` helpers).
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field
from schema.gym_rank import RankPresetKind, SubRankType

# member_activities.activity_type written on every member rank change
# (promotion, demotion, assignment, unassignment, enable-backfill). The
# member-detail progress anchor filters on this same value.
RANK_CHANGED_ACTIVITY_TYPE = "rank_changed"


class RankResponse(BaseModel):
    """A single ``gym_ranks`` row — one MAIN rank.

    ``sub_rank_count == 0`` means this main rank is itself the leaf
    (a member on it has ``current_sub_index`` NULL); ``N >= 1`` means
    ``N`` leaf sub-positions (``current_sub_index`` in ``[0, N-1]``).
    Sub-rank labels are derived from the gym's ``sub_rank_type`` + the
    index, so they are not carried on this row.
    """

    rank_id: UUID
    gym_id: UUID
    main_rank_num_order: int
    name: str
    image_url: str | None = None
    classes_to_next_major: int
    sub_rank_count: int
    sub_rank_image_overrides: dict = Field(default_factory=dict)
    created_at: datetime


class RankListResponse(BaseModel):
    """A gym's ladder plus its ``sub_rank_type``.

    ``sub_rank_type`` is returned once so the client can render every
    row's sub-rank labels without a second call.
    """

    items: list[RankResponse]
    sub_rank_type: SubRankType


class RankCreateRequest(BaseModel):
    """Body for POST /api/v1/ranks/."""

    gym_id: UUID
    main_rank_num_order: int = Field(ge=0)
    name: str = Field(min_length=1)
    classes_to_next_major: int = Field(ge=0)
    sub_rank_count: int = Field(ge=0, default=0)
    image_url: str | None = None
    sub_rank_image_overrides: dict = Field(default_factory=dict)


class RankUpdateData(BaseModel):
    """Mutable fields on a ``gym_ranks`` row.

    ``main_rank_num_order`` is deliberately absent — ``POST
    /ranks/reorder`` is the only mover of ladder positions (it is
    update-immutable). ``image_url`` and ``sub_rank_image_overrides``
    ARE writable now: the belt image is a user field (preset default
    plus manual override in the edit UI), and the per-sub overrides map
    is persist-only (never pruned — shrinking ``sub_rank_count`` clamps
    members but leaves dormant overrides intact).
    """

    name: str | None = Field(default=None, min_length=1)
    classes_to_next_major: int | None = Field(default=None, ge=0)
    sub_rank_count: int | None = Field(default=None, ge=0)
    image_url: str | None = None
    sub_rank_image_overrides: dict | None = None


class RankUpdateRequest(BaseModel):
    """Body for PUT /api/v1/ranks/{rank_id}."""

    data: RankUpdateData


class RankPresetResponse(BaseModel):
    """A single ``rank_presets`` row — one MAIN rank of a preset ladder."""

    preset_id: UUID
    preset_kind: RankPresetKind
    main_rank_num_order: int
    name: str
    image_url: str | None = None
    classes_to_next_major: int
    sub_rank_count: int
    implied_sub_rank_type: SubRankType | None = None


class RankPresetListResponse(BaseModel):
    """Flat preset list for a single ``preset_kind``."""

    items: list[RankPresetResponse]


class AllPresetsGroupedResponse(BaseModel):
    """Every preset ladder, keyed by ``preset_kind`` (flat main rows)."""

    presets: dict[RankPresetKind, list[RankPresetResponse]]


class FromPresetRequest(BaseModel):
    """Body for POST /api/v1/ranks/from-preset."""

    gym_id: UUID
    preset_kind: RankPresetKind


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

    ``new_rank`` is the member's MAIN rank after the change (``None``
    when unassigned). ``new_sub_index`` is the leaf position within it
    (``None`` when the rank has no sub-ranks, or when unassigned);
    ``new_sub_label`` / ``new_display_name`` are the derived labels.
    """

    member_id: UUID
    new_rank: RankResponse | None = None
    new_sub_index: int | None = None
    new_sub_label: str | None = None
    new_display_name: str | None = None


class RankPromoteMemberRequest(BaseModel):
    """Body for POST /api/v1/ranks/promote-member.

    Advances the member one leaf up the gym's ordered ladder — the
    next sub-position within the current main rank, else the base leaf
    of the next main rank. A rank-less member is assigned the lowest
    leaf.
    """

    gym_id: UUID
    member_id: UUID


class RankSetMemberRequest(BaseModel):
    """Body for POST /api/v1/ranks/set-member-rank.

    Sets the member to an explicit leaf (correction / demotion /
    assignment), or to no rank when ``rank_id`` is ``None``. When the
    target rank has sub-ranks, ``sub_index`` must be in
    ``[0, sub_rank_count - 1]``; when it has none, ``sub_index`` is
    forced to ``None``.
    """

    gym_id: UUID
    member_id: UUID
    rank_id: UUID | None = None
    sub_index: int | None = None


class RankReorderItem(BaseModel):
    """One rank's target main position in a bulk reorder."""

    rank_id: UUID
    main_rank_num_order: int = Field(ge=0)


class RankReorderRequest(BaseModel):
    """Body for POST /api/v1/ranks/reorder.

    The full desired ordering for the gym's ENTIRE ladder — every
    rank exactly once, positions unique. Applied as a two-phase
    update so the ``UNIQUE (gym_id, main_rank_num_order)`` constraint
    is never transiently violated.
    """

    gym_id: UUID
    ranks: list[RankReorderItem]


# ---------- paginated member reads (ready-to-promote / in-rank) ----------


class MembersReadyToPromoteRequest(BaseModel):
    """Query for GET /api/v1/ranks/ready-to-promote."""

    gym_id: UUID
    start_index: int = Field(ge=0, default=0)
    count: int = Field(ge=1, default=25)


class MembersReadyToPromoteRow(BaseModel):
    """One member on the ready-to-promote board.

    ``classes_since`` is attendance since the member's last rank change
    (the progress anchor); ``step_denominator`` is the classes needed to
    reach the next leaf (an even split of ``classes_to_next_major`` when
    the rank has sub-ranks, else the full major threshold).
    """

    member_id: UUID
    name: str
    avatar_url: str | None = None
    main_rank_id: UUID
    main_name: str
    current_sub_index: int | None = None
    sub_label: str | None = None
    image_url: str | None = None
    classes_since: int
    step_denominator: int | None = None


class MembersReadyToPromoteResponse(BaseModel):
    """Paginated ready-to-promote board (proximity-sorted)."""

    items: list[MembersReadyToPromoteRow]
    total_count: int


class MembersInRankRequest(BaseModel):
    """Query for GET /api/v1/ranks/{rank_id}/members."""

    gym_id: UUID
    rank_id: UUID
    start_index: int = Field(ge=0, default=0)
    count: int = Field(ge=1, default=25)


class MembersInRankRow(BaseModel):
    """One member currently on a given main rank."""

    member_id: UUID
    name: str
    avatar_url: str | None = None
    current_sub_index: int | None = None
    sub_label: str | None = None
    classes_since: int
    step_denominator: int | None = None


class MembersInRankResponse(BaseModel):
    """Paginated members on one main rank (ordered by sub-index)."""

    items: list[MembersInRankRow]
    total_count: int
