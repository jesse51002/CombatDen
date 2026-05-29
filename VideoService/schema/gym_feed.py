"""The public gym-browser projection: a slim, paginated view of the gyms.

Mirrors ``VideosFeed`` / ``VideoCard``. The gym is now the entry point — you
browse gyms, pick one, then load the **theme it carries** (``GymCard.theme``)
and fetch that gym's videos / classes / rewards. ``GymCard`` is the slim per-gym
card a picker renders; ``GymsPage`` is one page. Both are built from the full
``Gym`` and expose only what a browsable picker needs.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

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
