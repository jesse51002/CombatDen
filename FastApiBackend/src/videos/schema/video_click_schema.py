"""Pydantic response model for a member opening a video from the FEED.

The rec surface has its own click contract (``VideoRecClickResponse`` in
``video_recs_schema.py``) because a rec click ALSO stamps the served
``member_video_recs`` row and is therefore idempotent. A feed click has no rec
row to stamp: it is APPEND-ONLY taste signal, so every open logs a row and the
response only echoes which video was logged.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class MemberVideoClickResponse(BaseModel):
    """Result of a member opening a video from their gym's feed."""

    model_config = ConfigDict(extra="ignore")

    video_id: str
