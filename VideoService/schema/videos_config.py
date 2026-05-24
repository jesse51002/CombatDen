"""The `videos_config.yaml` contract: a company's video-discovery brief.

`VideoSearch` and `VideosConfig` form one tight unit, so they share a file.
Both are `extra="forbid"` — any stray key fails validation loudly. One YAML
document per company under `apps/<app_id>/videos_config.yaml`.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema.video_type import VideoType


class VideoSearch(BaseModel):
    """One YouTube search prompt plus its content-genre tags."""

    model_config = ConfigDict(extra="forbid")

    # The literal search prompt; this is what the later batch script feeds to
    # YouTube. Non-empty.
    query: str = Field(min_length=1)
    # One or more genre tags. A single search can legitimately span genres
    # (e.g. a how-to that is also entertaining), so this is a non-empty list.
    tags: list[VideoType] = Field(min_length=1)


class VideosConfig(BaseModel):
    """A company's video-discovery brief. The whole writable surface."""

    model_config = ConfigDict(extra="forbid")

    company_name: str = Field(min_length=2)  # display name of the business
    type: str = Field(min_length=2)  # business / niche type (e.g. "Muay Thai gym")
    videos_desc: str = Field(min_length=2)  # prose: the kinds of videos worth surfacing
    avoid_desc: str = Field(min_length=2)  # prose: content to avoid / exclude
    # At least one search; still capped at 20 and ideally spread across the
    # VideoType spectrum.
    searches: list[VideoSearch] = Field(min_length=1, max_length=20)
    # Channels the company wants prioritized — their own and/or ones they like.
    # Free-form for now (a name, @handle, or URL); a later step will resolve and
    # weight these deterministically. Optional: not every company has any.
    priority_channels: list[str] = Field(default_factory=list)
