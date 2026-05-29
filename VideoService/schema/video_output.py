"""One pooled video — the shared video pool is a folder of these.

`VideoOutput` is the per-video record under ``videos/<video_id>.yaml`` (the
single-tenant shared pool). It is `extra="ignore"` — these documents are
machine-written from the Apify scraper, so we tolerate (and drop) any field we
don't model rather than fail loudly. There is no manifest wrapper: the pool is
simply ``list[VideoOutput]`` loaded from the ``videos/`` directory.

Fields are kept to the minimum the app renders, plus a few (`description`,
`like_count`, `channel_url`, `source_queries`) carried for validation and
data-quality checks.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema.gym_type import GymType
from schema.video_type import VideoType


class VideoOutput(BaseModel):
    """One de-duplicated pooled video."""

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
    # Total runtime in seconds. None when the source didn't report a duration
    # (e.g. a live broadcast). A classifier signal + a length badge for clients.
    duration_seconds: int | None = None
    # The video's single genre, assigned by the tagging pass from the video's
    # actual content. None until `scripts/classify` runs.
    tag: VideoType | None = None
    # The disciplines this video is relevant to, assigned by the tagging pass —
    # a separate axis from `tag` (genre). A clip can belong to several (e.g.
    # `[kettlebell, rowing]`). Pure content classification that routes the video
    # into the candidate slices gyms scan; NOT an approval (approval is per-gym,
    # held on the gym's `good_video_ids` / `rejected_video_ids`). Empty until tagged.
    gym_type: list[GymType] = Field(default_factory=list)
    # The literal search query (or queries) that surfaced this video — for
    # tracing why a video is here and for data checks.
    source_queries: list[str] = Field(min_length=1)
    # Best (lowest) position this video held across the searches that surfaced
    # it. 0 = top result; lower is more relevant.
    relevance_index: int = Field(ge=0)
    # Why the transcript came back empty (provider reason / `not_returned`). None
    # when a transcript was fetched or before fetching. A data/diagnostic field.
    transcript_error: str | None = None
    # Full caption text (the strongest signal for the tagger; truncated at
    # prompt-build). None when the video has no captions / fetch failed. Kept LAST
    # so it sits at the bottom of each per-video file.
    transcript: str | None = None
