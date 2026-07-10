"""Pydantic models for the video-gym template catalog.

The template catalog is the set of slug-keyed ``template_gym*`` templates that the
preset import copies FROM. These schemas are used by the public-read template
endpoints under ``/api/v1/presets/templates``.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import ParentGymType


class VideoTemplateCard(BaseModel):
    """One template, exactly the fields a template picker renders.

    Slug catalog card. ``video_gym_id`` is the template slug (the ``template_gym``
    catalog key), renamed from the generic ``gym_id`` for clarity now that real
    UUID-keyed gyms live alongside the templates.
    """

    model_config = ConfigDict(extra="ignore")

    video_gym_id: str  # the template slug (template_gym catalog key)
    gym_type: list[GymType]  # the template's fine discipline(s)
    # The coarse parent bucket (the 8-bucket category) the picker filters by,
    # derived from the template's primary discipline.
    parent_gym_type: ParentGymType
    # The design id to brand with when this template is picked.
    theme: str
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
