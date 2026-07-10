"""Pydantic models for the videos domain.

The live gym feed (``GymVideo*`` / ``GymFeed*``): keyed by ``gyms.gym_id``
(UUID), read from the ``gym_video_*`` tables and the shared ``video`` pool.
The owner edits this feed by hand via ``VideoAddRequest`` (add one YouTube
link) and deletes/keeps.

The genre tag reuses ``VideoGenre`` from the Database package (the Postgres
``video_genre`` enum); ``GymType`` / ``ParentGymType`` / ``BigGroup`` are the
videos domain's own mapping enums.

Template catalog schemas have moved to ``src/presets/schema/presets_templates_schema.py``.
Showcase schemas have moved to ``src/theme/schema/theme_schema.py``.
"""

from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, computed_field
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_big_group import BigGroup, big_group_for
from src.videos.schema.videos_gym_type import GymType  # noqa: F401 — re-exported
from src.videos.schema.videos_parent_gym_type import ParentGymType  # noqa: F401 — re-exported

# ── YouTube metadata (owner-added video) ─────────────────────────────


class YouTubeVideoMetadata(BaseModel):
    """The real metadata fetched for one owner-added video — exactly the fields
    the ``video`` pool row stores. ``channel_avatar_url`` is best-effort (empty
    when the channel fetch failed)."""

    model_config = ConfigDict(extra="ignore")

    title: str
    channel_name: str
    channel_url: str
    thumbnail_url: str
    channel_avatar_url: str = ""
    view_count: int | None = None
    duration_seconds: int | None = None


# ── Live gym feed (UUID-keyed gym_video_*) ───────────────────────────


class GymVideoCard(BaseModel):
    """One video, exactly the fields the frontend renders.

    Built straight from a shared-pool ``video`` row (``from_attributes``); the
    genre ``tag`` is the Postgres ``video_genre`` enum.
    """

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    # The shared-pool video id (YouTube id). Required — every card carries it so
    # the client can record a rec click / owner-delete by id.
    video_id: str
    url: str
    title: str
    thumbnail_url: str
    channel_name: str
    channel_url: str
    channel_avatar_url: str
    view_count: int | None = None  # the "views" label; None when hidden
    duration_seconds: int | None = None  # runtime; for a length badge
    # 0 = top search hit; lower is more relevant. For secondary sorting.
    relevance_index: int = Field(ge=0)
    # The video's single genre tag, assigned by the pool tagging pass. None
    # until the pool is tagged; clients group on it.
    tag: VideoGenre | None = None
    # True when this card is an owner-added "Your videos" row (feed
    # video_run_id IS NULL). The merged feed selects it; other read paths that
    # don't carry it fall back to False (extra="ignore" + default).
    owner_added: bool = False
    # Whether the video has a video_rag embedding yet. The merged serve feed is
    # enriched by construction (INNER JOIN video_rag) so it stays True; only the
    # UNGATED owner management listing sets it False to badge "processing…".
    enriched: bool = True

    @computed_field  # type: ignore[prop-decorator]
    @property
    def big_group(self) -> BigGroup | None:
        """The coarse educational/entertainment sort — the frontend's primary
        grouping. Derived from `tag`; None until classified."""
        return big_group_for(self.tag) if self.tag is not None else None


class VideoAddRequest(BaseModel):
    """The owner-add payload: a single YouTube link (or a bare 11-char id).

    The backend extracts the YouTube video id, fetches the video's real metadata
    from the YouTube Data API (title / channel / thumbnail / views / duration /
    channel avatar), stores it on the shared-pool row, and adds it to the gym's
    served feed.
    """

    model_config = ConfigDict(extra="ignore")

    url: str = Field(min_length=1)


class VideoRemoveRequest(BaseModel):
    """The owner-remove payload: an optional free-text reason.

    ``owner=false`` (scan-run rejection): stores this reason as
    ``curation_reason`` on the feed row. ``owner=true`` (Your Videos
    hard-delete): the reason is ignored. No removal-log row is written.
    The body is optional — a remove with no reason is allowed.
    """

    model_config = ConfigDict(extra="ignore")

    reason: str | None = None


class VideoKeepRequest(BaseModel):
    """The owner-keep payload: an optional free-text reason for keeping / un-
    rejecting a video. The reason is stored on the feed row as
    ``curation_reason`` so the feed-learning refiner can include it when
    widening the spec's include criteria. The body is optional — a keep with
    no reason is allowed. Field name ``accept_reason`` is stable (the CRM
    posts ``{"accept_reason": "..."}``); the service maps it to the DB column."""

    model_config = ConfigDict(extra="ignore")

    accept_reason: str | None = None


class GymVideosFeed(BaseModel):
    """A gym's served video feed: one page of the slim, public projection.

    The endpoint paginates with ``limit``/``offset``: ``videos`` is the current
    page (after the ``video_type``/``big_group`` genre filters), and ``total`` is
    how many videos matched the filters before slicing.
    """

    model_config = ConfigDict(extra="ignore")

    total: int = Field(ge=0)  # videos matching the filters, before pagination
    limit: int = Field(ge=1)  # page size that produced `videos`
    offset: int = Field(ge=0)  # start index of this page
    videos: list[GymVideoCard] = Field(default_factory=list)


class GymFeedSection(BaseModel):
    """One genre's preview row: the tag plus its first few videos, in feed
    order."""

    model_config = ConfigDict(extra="ignore")

    tag: VideoGenre
    videos: list[GymVideoCard] = Field(default_factory=list)


class GymFeedPreview(BaseModel):
    """The whole "All" preview in one response: one section per genre present in
    the gym's feed, each capped to a few videos, in feed order. Each genre is
    sampled individually server-side, so no genre is starved by global
    pagination."""

    model_config = ConfigDict(extra="ignore")

    sections: list[GymFeedSection] = Field(default_factory=list)


def build_feed_page_result(rows: list) -> tuple[list[GymVideoCard], int]:
    """Build ``(cards, total)`` from a ``COUNT(*) OVER()`` paginated result set.

    Shared tail for any feed-page SQL query that selects a ``total`` column
    and fields that map to :class:`GymVideoCard`.  Each row is validated via
    :meth:`GymVideoCard.model_validate`; a row that fails validation is
    silently skipped so one bad row does not break the whole page.
    Returns ``([], 0)`` when no rows were returned.
    """
    if not rows:
        return [], 0
    total: int = rows[0]["total"]
    cards: list[GymVideoCard] = []
    for row in rows:
        try:
            cards.append(GymVideoCard.model_validate(dict(row)))
        except ValueError:
            continue
    return cards, total


# ── Live gym spec (gym_video_spec / gym_video_spec_latest) ───────────


class GymVideoSpecView(BaseModel):
    """A real gym's live video spec — the projection of its LATEST
    ``gym_video_spec`` version (read via the ``gym_video_spec_latest`` view; the
    spec is append-only versioned). The short pair is display-only; the long pair
    is the scan criteria. ``imported_from`` records the template a preset import
    seeded this from (NULL once agent/hand-authored)."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    gym_type: list[str]
    short_videos_desc: str | None = None
    short_avoid_desc: str | None = None
    videos_desc: str
    avoid_desc: str
    imported_from: str | None = None
