"""Pydantic response models for a member's video recommendation.

A rec is a single served feed card (:class:`GymVideoCard`) wrapped in a
:class:`MemberVideoRec` that carries the served ``rec_id`` (the client posts it
back on a click) and the video's genre ``category``. The rec surface serves ONE
video at a time, rotating through the genre categories in
``settings.video_rec_category_rotation`` so a member sees a spread over time. The
pick is the top of the unified feed read (``VideoFeedService.rank_page_for_member``,
``limit=1``) for that genre — cosine order to the member's taste embedding (gym
relevance when they have no embedding yet), with the decayed already-served
penalty advancing the pick on a re-serve. The card already carries its
``video_id``, so no separate candidate wrapper is needed.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_schema import GymVideoCard


class MemberVideoRec(BaseModel):
    """One recommendation served to a member (the rotating single pick).

    ``rec_id`` is the just-written ``member_video_recs`` row — the client posts
    it back to the click endpoint. ``category`` is the served video's genre.
    """

    model_config = ConfigDict(extra="ignore")

    rec_id: UUID
    category: VideoGenre
    video: GymVideoCard


class VideoRecClickResponse(BaseModel):
    """Result of a member opening (clicking) a recommendation."""

    model_config = ConfigDict(extra="ignore")

    clicked: bool  # True = first click (stamped + logged); False = idempotent repeat
    video_id: str
