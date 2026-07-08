"""Pydantic response models for a member's video recommendation.

A rec is a single served feed card (:class:`GymVideoCard`) wrapped in a
:class:`MemberVideoRec` that carries the served ``rec_id`` (the client posts it
back on a click) and the video's genre ``category``. The rec surface serves ONE
video at a time, rotating through the genre categories in
``settings.video_rec_category_rotation`` so a member sees a spread over time. The
pick is ranked by PURE cosine similarity to the member's video-taste embedding
(gym relevance when they have no embedding yet) — no composite blend, no stored
score. :class:`RecCandidate` is the internal value the feed service returns for a
single ranked pick (the video id plus its card) before it is recorded.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_schema import GymVideoCard


class RecCandidate(BaseModel):
    """One ranked recommendation pick before it is recorded.

    ``VideoFeedService.load_next_rec_video`` returns this so the service passes a
    typed value (not a raw row): ``video_id`` is the pool id to record, ``video``
    the card to return to the client.
    """

    model_config = ConfigDict(extra="ignore")

    video_id: str
    video: GymVideoCard


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
