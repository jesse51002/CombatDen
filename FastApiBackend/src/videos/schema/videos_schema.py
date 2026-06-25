"""Pydantic models for the videos domain.

Two surfaces, both read-only:

* **The slug-keyed template catalog** (``VideoTemplate*``) — the 76 hand-authored
  ``video_gym*`` templates the preset import copies FROM. Cards browse them; a
  detail serves one template's spec / classes / rewards.
* **A real gym's live content** (``GymVideo*`` / ``GymShowcase`` / ``GymFeed*``) —
  keyed by ``gyms.gym_id`` (UUID), read from the ``gym_video_*`` tables and the
  shared ``video`` pool. ``gym_video_feed`` is lean (no status column): every row
  is a served video, so there is no rejected-feed surface here.

The genre tag reuses ``VideoGenre`` from the Database package (the Postgres
``video_genre`` enum); ``GymType`` / ``ParentGymType`` / ``BigGroup`` are the
videos domain's own mapping enums.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, computed_field
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_big_group import BigGroup, big_group_for
from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import ParentGymType

# ── Template catalog (slug-keyed video_gym*) ─────────────────────────


class VideoTemplateCard(BaseModel):
    """One template, exactly the fields a template picker renders.

    Slug catalog card. ``video_gym_id`` is the template slug (the ``video_gym``
    catalog key), renamed from the generic ``gym_id`` for clarity now that real
    UUID-keyed gyms live alongside the templates.
    """

    model_config = ConfigDict(extra="ignore")

    video_gym_id: str  # the template slug (video_gym catalog key)
    gym_type: list[GymType]  # the template's fine discipline(s)
    # The coarse parent bucket (the 8-bucket category) the picker filters by,
    # derived from the template's primary discipline.
    parent_gym_type: ParentGymType
    # The design id to brand with when this template is picked.
    theme: str
    # The card art — the theme's celebration image, derived by the API from the
    # theme. Not stored on the template.
    celebration_image_url: str
    video_count: int = Field(ge=0)  # approved videos in this template's feed
    has_classes: bool  # whether class cards are authored
    has_rewards: bool  # whether reward cards are authored


class VideoTemplateCatalogPage(BaseModel):
    """One page of the template catalog: the slim cards plus pagination metadata.

    Paginated with ``limit``/``offset``: ``gyms`` is the current page and
    ``total`` is how many templates exist before slicing.
    """

    model_config = ConfigDict(extra="ignore")

    total: int = Field(ge=0)  # templates before pagination
    limit: int = Field(ge=1)  # page size that produced `gyms`
    offset: int = Field(ge=0)  # start index of this page
    gyms: list[VideoTemplateCard] = Field(default_factory=list)


class VideoTemplateSpecView(BaseModel):
    """A template's feed surface/avoid descriptions: a short ~2-sentence summary
    (``short_*``, optional until backfilled) shown by default, plus the full scan
    criteria (``videos_desc`` / ``avoid_desc``) revealed behind a "view full
    prompt"."""

    model_config = ConfigDict(extra="ignore")

    short_videos_desc: str | None = None
    short_avoid_desc: str | None = None
    videos_desc: str
    avoid_desc: str


class VideoTemplateClassCard(BaseModel):
    """One template class card: name, a horizontal class image, a description, and
    the instructor (name + bio + headshot). Template rows are non-null (authored),
    so every field is required."""

    model_config = ConfigDict(extra="ignore")

    name: str
    image_url: str
    description: str
    instructor_name: str
    instructor_bio: str
    instructor_image_url: str


class VideoTemplateRewardCard(BaseModel):
    """One template points-store reward: a title, an image, what the member pays
    on top of points (``price_label``), and the points cost."""

    model_config = ConfigDict(extra="ignore")

    title: str
    image_url: str
    price_label: str
    points_cost: int


class VideoTemplateDetail(BaseModel):
    """One template's full content detail, fetched by slug after it's picked.

    Everything a member-app surface renders except the paginated video feed: the
    feed ``specification`` (descriptions), the branded ``classes`` cards, and the
    points-store ``rewards``. ``classes`` / ``rewards`` are None until authored.
    """

    model_config = ConfigDict(extra="ignore")

    video_gym_id: str  # the template slug
    theme: str  # the design id to brand with — NOT a content key
    specification: VideoTemplateSpecView
    classes: list[VideoTemplateClassCard] | None = None  # None until authored
    rewards: list[VideoTemplateRewardCard] | None = None  # None until authored


# ── Live gym feed (UUID-keyed gym_video_*) ───────────────────────────


class GymVideoCard(BaseModel):
    """One video, exactly the fields the frontend renders.

    Built straight from a shared-pool ``video`` row (``from_attributes``); the
    genre ``tag`` is the Postgres ``video_genre`` enum.
    """

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    url: str
    title: str
    thumbnail_url: str
    channel_name: str
    channel_url: str
    channel_avatar_url: str
    view_count: int | None = None  # the "views" label; None when hidden
    duration_seconds: int | None = None  # runtime; for a length badge
    # 0 = top search hit; lower is more relevant. For secondary sorting.
    relevance_index: int = Field(ge=0)
    # The video's single genre tag, assigned by the pool tagging pass. None
    # until the pool is tagged; clients group on it.
    tag: VideoGenre | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def big_group(self) -> BigGroup | None:
        """The coarse educational/entertainment sort — the frontend's primary
        grouping. Derived from `tag`; None until classified."""
        return big_group_for(self.tag) if self.tag is not None else None


class GymVideosFeed(BaseModel):
    """A gym's served video feed: one page of the slim, public projection.

    The endpoint paginates with ``limit``/``offset``: ``videos`` is the current
    page (after the ``video_type``/``big_group`` genre filters), and ``total`` is
    how many videos matched the filters before slicing.
    """

    model_config = ConfigDict(extra="ignore")

    total: int = Field(ge=0)  # videos matching the filters, before pagination
    limit: int = Field(ge=1)  # page size that produced `videos`
    offset: int = Field(ge=0)  # start index of this page
    videos: list[GymVideoCard] = Field(default_factory=list)


class GymFeedSection(BaseModel):
    """One genre's preview row: the tag plus its first few videos, in feed
    order."""

    model_config = ConfigDict(extra="ignore")

    tag: VideoGenre
    videos: list[GymVideoCard] = Field(default_factory=list)


class GymFeedPreview(BaseModel):
    """The whole "All" preview in one response: one section per genre present in
    the gym's feed, each capped to a few videos, in feed order. Each genre is
    sampled individually server-side, so no genre is starved by global
    pagination."""

    model_config = ConfigDict(extra="ignore")

    sections: list[GymFeedSection] = Field(default_factory=list)


# ── Live gym spec + showcase (gym_video_spec / gym_classes / gym_rewards) ──


class GymVideoSpecView(BaseModel):
    """A real gym's live video spec — the projection of its ``gym_video_spec``
    row. The short pair is display-only; the long pair is the scan criteria. The
    ``imported_*`` provenance records the template a preset import seeded this
    from (NULL once hand-edited)."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    gym_type: list[str]
    short_videos_desc: str | None = None
    short_avoid_desc: str | None = None
    videos_desc: str
    avoid_desc: str
    imported_from: str | None = None
    imported_at: datetime | None = None


class ShowcaseClassCard(BaseModel):
    """One showcase class card built from a real gym's ``gym_classes`` row + its
    resolved instructor. Lenient: the prod ``gym_classes`` / ``gym_employees``
    columns are nullable, so every display field beyond ``name`` may be None."""

    model_config = ConfigDict(extra="ignore")

    name: str
    image_url: str | None = None
    description: str | None = None
    instructor_name: str | None = None
    instructor_bio: str | None = None
    instructor_image_url: str | None = None


class ShowcaseRewardCard(BaseModel):
    """One showcase reward card from a real gym's ``gym_rewards`` row. Lenient:
    ``image_url`` / ``price_label`` are nullable in prod."""

    model_config = ConfigDict(extra="ignore")

    title: str
    image_url: str | None = None
    price_label: str | None = None
    points_cost: int


class GymShowcase(BaseModel):
    """A real gym's showcase: its live video spec plus the branded class cards and
    points-store reward cards. ``spec`` is None until a spec row is authored;
    ``classes`` / ``rewards`` are possibly-empty lists."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    spec: GymVideoSpecView | None = None
    classes: list[ShowcaseClassCard] = Field(default_factory=list)
    rewards: list[ShowcaseRewardCard] = Field(default_factory=list)
