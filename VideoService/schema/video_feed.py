"""The public video feed the API serves: the slim, frontend-only projection of
a pooled ``VideoOutput``.

``VideoOutput`` (in ``video_output.py``) is the full pooled record; it carries a
few fields kept only for offline validation/data checks (``description``,
``like_count``, ``source_queries``). The API drops those and serves just what a
client renders. ``VideoCard`` and ``VideosFeed`` are that slim view;
``from_attributes`` lets FastAPI build them straight from a ``VideoOutput``.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, computed_field

from schema.big_group import BigGroup, big_group_for
from schema.video_type import VideoType


class VideoCard(BaseModel):
    """One video, exactly the fields the frontend renders."""

    model_config = ConfigDict(extra="ignore", from_attributes=True)

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
    tag: VideoType | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def big_group(self) -> BigGroup | None:
        """The coarse educational/entertainment sort — the frontend's primary
        grouping. Derived from `tag`; None until classified."""
        return big_group_for(self.tag) if self.tag is not None else None


class VideosFeed(BaseModel):
    """A company's served video feed: one page of the slim, public projection.

    The endpoint paginates with ``limit``/``offset``: ``videos`` is the current
    page (after the ``video_type``/``big_group`` genre filters), and ``total`` is
    how many videos matched the filters before slicing — so the client can
    compute how many pages remain. Every video here is already gym-approved (the
    feed is the gym's ``good_video_ids``), so there is no ``is_good`` filter.
    """

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    total: int = Field(ge=0)  # videos matching the filters, before pagination
    limit: int = Field(ge=1)  # page size that produced `videos`
    offset: int = Field(ge=0)  # start index of this page
    videos: list[VideoCard] = Field(default_factory=list)


class FeedSection(BaseModel):
    """One genre's preview row: the tag plus its first few videos, in feed
    order. ``from_attributes`` lets FastAPI build the cards from ``VideoOutput``."""

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    tag: VideoType
    videos: list[VideoCard] = Field(default_factory=list)


class FeedPreview(BaseModel):
    """The whole "All" preview in one response: one section per genre present in
    the gym's feed, each capped to a few videos, in feed order. Each genre is
    sampled individually server-side, so no genre is starved by global
    pagination — and the client makes one request instead of one per genre."""

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    sections: list[FeedSection] = Field(default_factory=list)
