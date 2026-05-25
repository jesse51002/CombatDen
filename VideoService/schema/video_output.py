"""The `videos_output.yaml` contract: the result of running a brief's searches.

`VideoOutput` and `VideosOutput` form one tight unit, so they share a file.
Unlike the rest of `schema/`, both are `extra="ignore"` — these documents are
machine-written from YouTube Data API responses, so we deliberately tolerate
(and drop) any field we don't model rather than fail loudly. That keeps the
batch resilient to YouTube API shape changes.

Fields are kept to the minimum the mobile app renders, plus a few
(`description`, `like_count`, `channel_url`) carried for later validation and
data-quality checks. Note: YouTube removed the public *dislike* count from the
Data API on 2021-12-13, so no dislike data exists to store.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from schema.video_type import VideoType


class VideoOutput(BaseModel):
    """One de-duplicated video surfaced by a brief's searches."""

    model_config = ConfigDict(extra="ignore")

    url: str  # watch link: https://www.youtube.com/watch?v=<id>
    title: str
    description: str  # carried for validation / data checks (not rendered)
    thumbnail_url: str
    channel_name: str  # the creator name
    channel_url: str  # https://www.youtube.com/channel/<channel_id>
    channel_avatar_url: str  # the creator's profile picture
    view_count: int | None = None  # None when stats are hidden
    like_count: int | None = None  # None when likes are hidden
    # Total runtime in seconds (from videos.list contentDetails). None when the
    # API didn't report a duration (e.g. a live broadcast). Fed to the
    # classifier as a signal and rendered as a length badge by clients.
    duration_seconds: int | None = None
    # The video's single genre, assigned by the classification pass from the
    # video's actual content (NOT from the search that surfaced it). None until
    # `scripts/classify` runs; it then sets exactly one tag.
    tag: VideoType | None = None
    # Whether this video belongs in the company's feed — the classification
    # pass's quality/relevance verdict. None until classified; clients filter
    # on it (off-niche videos are kept, not dropped).
    is_good: bool | None = None
    # The literal search query (or queries) that surfaced this video — useful
    # for tracing why a video is here and for data checks.
    source_queries: list[str] = Field(min_length=1)
    # Best (lowest) position this video held across the searches that surfaced
    # it. 0 = top result; lower is more relevant.
    relevance_index: int = Field(ge=0)


class VideosOutput(BaseModel):
    """The whole `videos_output.yaml`: one run's results for one company."""

    model_config = ConfigDict(extra="ignore")

    company_name: str
    app_id: str
    generated_at: datetime
    quota_units_estimate: int  # YouTube Data API units this run cost
    videos: list[VideoOutput] = Field(default_factory=list)
