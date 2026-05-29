"""The public gym-browser projection: a slim, paginated view of the gyms.

Mirrors ``VideosFeed`` / ``VideoCard``. The gym is the entry point — you browse
gyms (``GymCard`` / ``GymsPage``), pick one, then fetch that one gym's full
detail by ``gym_id`` (``GymDetail``: its classes, rewards, and feed spec — the
client reads this whole object into memory once) plus its paginated video feed
(``/gyms/{gym_id}/videos``, which needs paging). The ``theme`` carried on the
card/detail is used only for branding (loading the design), never to fetch
content.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema.class_output import ClassImage
from schema.gym import Gym, RewardCard
from schema.gym_type import GymType
from schema.parent_gym_type import ParentGymType


class GymCard(BaseModel):
    """One gym, exactly the fields a gym picker renders."""

    model_config = ConfigDict(extra="ignore")

    gym_id: str
    gym_type: list[GymType]  # the gym's fine discipline(s)
    # The coarse parent bucket (the 8-bucket category) the picker filters by,
    # derived from the gym's primary discipline.
    parent_gym_type: ParentGymType
    # The design id to load when this gym is picked — the theme lives on the gym.
    theme: str
    # The card art — the theme's celebration image, DERIVED by the API from the
    # theme (a CustomizationService-relative path the client absolutises, same as
    # the theme picker). Not stored on the gym.
    celebration_image_url: str
    video_count: int = Field(ge=0)  # approved videos in this gym's feed
    has_classes: bool  # whether class cards are authored
    has_rewards: bool  # whether reward cards are authored


class GymsPage(BaseModel):
    """One page of the gym browser: the slim cards plus pagination metadata.

    Paginated with ``limit``/``offset``: ``gyms`` is the current page and
    ``total`` is how many gyms exist before slicing, so the client can compute
    how many pages remain.
    """

    model_config = ConfigDict(extra="ignore")

    total: int = Field(ge=0)  # gyms before pagination
    limit: int = Field(ge=1)  # page size that produced `gyms`
    offset: int = Field(ge=0)  # start index of this page
    gyms: list[GymCard] = Field(default_factory=list)


class GymSpecificationView(BaseModel):
    """The feed's surface/avoid descriptions, the slim projection of the gym's
    ``GymSpecifications``: a short ~2-sentence summary (``short_*``, optional
    until backfilled) shown by default, plus the full scan criteria
    (``videos_desc`` / ``avoid_desc``) revealed behind a "view full prompt"."""

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    short_videos_desc: str | None = None
    short_avoid_desc: str | None = None
    videos_desc: str
    avoid_desc: str


class GymDetail(BaseModel):
    """One gym's full content detail, fetched by ``gym_id`` after it's picked.

    Everything a member-app surface renders *except* the paginated video feed:
    the feed ``specification`` (descriptions), the branded ``classes`` cards, and
    the points-store ``rewards``. Served verbatim from the gym; the client reads
    it into memory once on selection. ``theme`` is carried for branding only.
    """

    model_config = ConfigDict(extra="ignore")

    gym_id: str
    theme: str  # the design id to brand with — NOT a content key
    specification: GymSpecificationView
    classes: list[ClassImage] | None = None  # None until authored
    rewards: list[RewardCard] | None = None  # None until authored

    @classmethod
    def from_gym(cls, gym: Gym) -> GymDetail:
        """Project a full ``Gym`` to its served detail (drops the video id-lists
        and scan state — those reach the client via the paginated feed)."""
        return cls(
            gym_id=gym.gym_id,
            theme=gym.theme,
            specification=GymSpecificationView.model_validate(
                gym.videos.specification, from_attributes=True
            ),
            classes=gym.classes,
            rewards=gym.rewards,
        )
