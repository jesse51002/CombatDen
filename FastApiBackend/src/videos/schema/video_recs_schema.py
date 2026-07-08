"""Pydantic response models for a member's video recommendation.

A rec is a single served feed card (:class:`RecommendedVideoCard` — a
:class:`GymVideoCard` plus its blended ``score`` and an ``already_recommended``
flag) wrapped in a :class:`MemberVideoRec` that carries the served ``rec_id``
(the client posts it back on a click) and the video's genre ``category``. The
rec surface serves ONE video at a time, rotating through the genre categories in
``settings.video_rec_category_rotation`` so a member sees a spread over time.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict
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


class MemberVideoRec(BaseModel):
    """One recommendation served to a member (the rotating single pick).

    ``rec_id`` is the just-written ``member_video_recs`` row — the client posts
    it back to the click endpoint. ``category`` is the served video's genre.
    """

    model_config = ConfigDict(extra="ignore")

    rec_id: UUID
    category: VideoGenre
    video: RecommendedVideoCard


class VideoRecClickResponse(BaseModel):
    """Result of a member opening (clicking) a recommendation."""

    model_config = ConfigDict(extra="ignore")

    clicked: bool  # True = first click (stamped + logged); False = idempotent repeat
    video_id: str
