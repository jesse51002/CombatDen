"""The fetched-feed contract: the result of running a brief's searches.

`VideoOutput`, `VideosManifest`, and `VideosOutput` form one tight unit, so they
share a file. On disk the feed is split — `videos_output.yaml` holds a
`VideosManifest` (run metadata) and each video is its own file under `videos/`
(a `VideoOutput`); `VideosOutput` is the in-memory aggregate that reassembles
the two. Unlike the rest of `schema/`, all three are `extra="ignore"` — these
documents are machine-written from YouTube Data API responses, so we
deliberately tolerate (and drop) any field we don't model rather than fail
loudly. That keeps the batch resilient to YouTube API shape changes.

Fields are kept to the minimum the mobile app renders, plus a few
(`description`, `like_count`, `channel_url`) carried for later validation and
data-quality checks. Note: YouTube removed the public *dislike* count from the
Data API on 2021-12-13, so no dislike data exists to store.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from schema.verdict_reason import VerdictReason
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
    # Why this video is NOT in the feed, set with `is_good=False` by the classify
    # pass (no transcript / errored out / LLM rejected). None when the video is
    # good or not yet classified. A data/diagnostic field — not served.
    reason: VerdictReason | None = None
    # The literal search query (or queries) that surfaced this video — useful
    # for tracing why a video is here and for data checks.
    source_queries: list[str] = Field(min_length=1)
    # Best (lowest) position this video held across the searches that surfaced
    # it. 0 = top result; lower is more relevant.
    relevance_index: int = Field(ge=0)
    # Why the transcript fetch came back empty, set by `scripts/transcripts` when
    # it can't get one — the provider's reason (e.g. `TranscriptNotFound`,
    # `AgeRestricted`, `VideoUnavailable`) or `not_returned`. None when a
    # transcript was fetched, or before the transcripts pass has run.
    transcript_error: str | None = None
    # Full caption text, fetched by `scripts/transcripts` (Apify). The strongest
    # content signal for the classifier — stored whole and untruncated here (the
    # classifier truncates at prompt-build). None when the video has no captions,
    # fetching failed, or the transcripts pass hasn't run. Kept LAST so it sits
    # at the bottom of each per-video file.
    transcript: str | None = None


class VideosManifest(BaseModel):
    """The per-app ``videos_output.yaml``: run-level metadata only.

    The videos themselves live one-per-file under ``apps/<app_id>/videos/``;
    this manifest holds just the fields that describe the run as a whole.
    ``VideosService`` reassembles a :class:`VideosOutput` from this manifest plus
    the per-video files, so consumers keep seeing one aggregate object.
    """

    model_config = ConfigDict(extra="ignore")

    company_name: str
    app_id: str
    generated_at: datetime
    # The brief's search queries this fetch ran (copied from videos_config.yaml),
    # so the output records what produced it without a cross-reference.
    queries: list[str] = Field(default_factory=list)
    quota_units_estimate: int  # YouTube Data API units this run cost
    # Estimated USD spent fetching transcripts (Apify), accumulated across runs
    # since each run only fetches the still-missing videos. None until
    # `make transcripts` has run.
    transcript_cost_usd: float | None = None
    # Estimated USD the last classification pass spent (litellm's own pricing).
    # None until `make classify` has run.
    classification_cost_usd: float | None = None


class VideosOutput(BaseModel):
    """One company's full fetched feed: the manifest fields plus every video.

    The in-memory aggregate the API, classifier, and audit all consume. On disk
    it is split into a :class:`VideosManifest` (``videos_output.yaml``) and one
    :class:`VideoOutput` per file under ``videos/`` — it is no longer written to
    a single document.
    """

    model_config = ConfigDict(extra="ignore")

    company_name: str
    app_id: str
    generated_at: datetime
    queries: list[str] = Field(default_factory=list)  # the searches this fetch ran
    quota_units_estimate: int  # YouTube Data API units this run cost
    transcript_cost_usd: float | None = None  # USD spent fetching transcripts (cumulative)
    classification_cost_usd: float | None = None  # USD the last classify pass spent
    videos: list[VideoOutput] = Field(default_factory=list)
