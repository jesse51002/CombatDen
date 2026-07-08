"""Pydantic response models for member video recommendations.

A rec is a served feed card plus its blended ``score`` and an
``already_recommended`` flag (True when the member has been served this video
before, under any genre category). Results are grouped by the video's genre
(:class:`VideoGenre`) — top-k per category, one entry per genre that appears —
so the response surfaces a spread of the member's actual content genres.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field
from schema.video import VideoGenre

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


class RecCategory(BaseModel):
    """One genre category's ranked recommendations."""

    model_config = ConfigDict(extra="ignore")

    category: VideoGenre
    videos: list[RecommendedVideoCard] = Field(default_factory=list)


class MemberVideoRecsResponse(BaseModel):
    """A member's recommendations, one entry per genre category that appears."""

    model_config = ConfigDict(extra="ignore")

    categories: list[RecCategory] = Field(default_factory=list)


class VideoRecClickResponse(BaseModel):
    """Result of a member opening (clicking) a recommendation."""

    model_config = ConfigDict(extra="ignore")

    clicked: bool  # True = first click (stamped + logged); False = idempotent repeat
    video_id: str
