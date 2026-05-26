"""The public video feed the API serves: the slim, frontend-only projection of
``videos_output.yaml``.

``VideoOutput`` (in ``video_output.py``) is the full cached record; it carries a
few fields kept only for offline validation/data checks (``description``,
``like_count``, ``source_queries``) plus run accounting (``quota_units_estimate``).
The API drops all of those and serves just what a client renders. ``VideoCard``
and ``VideosFeed`` are that slim view; ``from_attributes`` lets FastAPI build
them straight from the loaded ``VideosOutput`` object.
"""

from __future__ import annotations

from datetime import datetime

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
    # The video's single genre tag, assigned by the classification pass. None
    # until a feed is classified; clients group on it.
    tag: VideoType | None = None
    # The classifier's keep/drop verdict; clients filter off-niche videos.
    # None until classified.
    is_good: bool | None = None

    @computed_field  # type: ignore[prop-decorator]
    @property
    def big_group(self) -> BigGroup | None:
        """The coarse educational/entertainment sort — the frontend's primary
        grouping. Derived from `tag`; None until classified."""
        return big_group_for(self.tag) if self.tag is not None else None


class VideosFeed(BaseModel):
    """A company's served video feed: one page of the slim, public projection.

    The endpoint paginates with ``limit``/``offset``: ``videos`` is the current
    page (after the ``is_good``/``video_type``/``big_group`` filters), and
    ``total`` is how many videos matched the filters before slicing — so the
    client can compute how many pages remain.
    """

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    company_name: str
    app_id: str
    generated_at: datetime
    total: int = Field(ge=0)  # videos matching the filters, before pagination
    limit: int = Field(ge=1)  # page size that produced `videos`
    offset: int = Field(ge=0)  # start index of this page
    videos: list[VideoCard] = Field(default_factory=list)
