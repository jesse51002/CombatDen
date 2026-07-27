"""Pydantic models for the theme domain.

The showcase surface is a gym's branded class cards and points-store reward
cards — the content that the mobile app renders on the gym's home/profile
surface. No video spec is included here; the spec lives in the ``videos``
domain and is served separately.
"""

from __future__ import annotations

from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ShowcaseCategory(StrEnum):
    """The 8-bucket demo-content vocabulary the standalone theme browser keys
    its bundled showcase cards by.

    This mirrors ``ParentGymType`` in
    ``src/videos/schema/videos_parent_gym_type.py`` (the discipline roll-up),
    but is deliberately NOT imported from it: the videos domain owns gym
    business logic, while this enum is the theme domain's own wire vocabulary
    for static demo content. Keep the two value sets in sync by hand."""

    fighting = "Fighting"
    yoga = "Yoga"
    pilates = "Pilates"
    barre = "Barre"
    hiit = "HIIT"
    cardio = "Cardio"
    dance = "Dance"
    wellness = "Wellness"


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
    """One showcase reward card from a real gym's ``gym_rewards`` row.

    ``image_url`` / ``price_label`` are actually NOT NULL on ``gym_rewards``
    (every reward has both); kept ``Optional`` here anyway as a defensive,
    lenient parse for this read-only showcase surface, not because the
    columns can be null.
    """

    model_config = ConfigDict(extra="ignore")

    title: str
    image_url: str | None = None
    price_label: str | None = None
    points_cost: int


class GymShowcase(BaseModel):
    """A real gym's showcase: branded class cards and points-store reward cards.
    ``classes`` / ``rewards`` are possibly-empty lists."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    classes: list[ShowcaseClassCard] = Field(default_factory=list)
    rewards: list[ShowcaseRewardCard] = Field(default_factory=list)
    # The gym's saved ThemeService design id; the mobile app uses it to
    # re-theme itself to the gym's branding. None until the gym picks a theme.
    theme_design_id: str | None = None


class ShowcaseGroupDefaults(BaseModel):
    """One category's bundled demo class and reward cards. Reuses the same
    card models as a real gym's showcase — the demo content is production-shaped,
    not a special-case model."""

    model_config = ConfigDict(extra="ignore")

    classes: list[ShowcaseClassCard] = Field(default_factory=list)
    rewards: list[ShowcaseRewardCard] = Field(default_factory=list)


class ShowcaseDefaults(BaseModel):
    """The standalone theme browser's static demo content: bundled class and
    reward cards keyed by ``ShowcaseCategory``. Served from a repo YAML file
    (no database) when no real gym is selected."""

    model_config = ConfigDict(extra="ignore")

    categories: dict[ShowcaseCategory, ShowcaseGroupDefaults] = Field(
        default_factory=dict
    )
