"""Pydantic response models for member video recommendations.

A rec is a served feed card plus its blended ``score`` and an
``already_recommended`` flag (True when the member has been served this video
before, under any bucket). Results are grouped by :class:`MoodBucket` — top-k
per bucket, so the response never collapses to a single genre.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field
from schema.video import MoodBucket

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_schema import GymVideoCard


class RecommendedVideoCard(GymVideoCard):
    """A served feed card enriched with its recommendation score + seen flag.

    Extends :class:`GymVideoCard` (same rendered fields + the derived
    ``big_group``) with the RAG-blended ``score`` and whether this member has
    been recommended the video before.
    """

    score: float
    already_recommended: bool = False


class RecBucket(BaseModel):
    """One mood bucket's ranked recommendations."""

    model_config = ConfigDict(extra="ignore")

    bucket: MoodBucket
    videos: list[RecommendedVideoCard] = Field(default_factory=list)


class MemberVideoRecsResponse(BaseModel):
    """A member's recommendations, one entry per mood bucket (all 5 present)."""

    model_config = ConfigDict(extra="ignore")

    buckets: list[RecBucket] = Field(default_factory=list)
