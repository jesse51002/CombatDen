"""Pydantic models for the theme domain.

The showcase surface is a gym's branded class cards and points-store reward
cards — the content that the mobile app renders on the gym's home/profile
surface. No video spec is included here; the spec lives in the ``videos``
domain and is served separately.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


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
    """A real gym's showcase: branded class cards and points-store reward cards.
    ``classes`` / ``rewards`` are possibly-empty lists."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    classes: list[ShowcaseClassCard] = Field(default_factory=list)
    rewards: list[ShowcaseRewardCard] = Field(default_factory=list)
