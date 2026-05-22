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

from schema.big_group import BigGroup, big_groups_for_tags
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
    # 0 = top search hit; lower is more relevant. For secondary sorting.
    relevance_index: int = Field(ge=0)
    tags: list[VideoType] = Field(min_length=1)  # fine-grained genre tags

    @computed_field  # type: ignore[prop-decorator]
    @property
    def big_groups(self) -> list[BigGroup]:
        """The coarse educational/entertainment sort — the frontend's primary
        grouping. Derived from `tags`; a video can be in both."""
        return big_groups_for_tags(self.tags)


class VideosFeed(BaseModel):
    """A company's served video feed: the slim, public projection."""

    model_config = ConfigDict(extra="ignore", from_attributes=True)

    company_name: str
    app_id: str
    generated_at: datetime
    videos: list[VideoCard] = Field(default_factory=list)
