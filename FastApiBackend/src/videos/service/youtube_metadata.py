"""YouTube Data API v3 client — real metadata for an owner-added video.

When an owner adds a single video to a gym's feed, the backend fetches that
video's real title / channel / thumbnail / view count / duration from the
official YouTube Data API (``videos.list``), plus the creator's channel avatar
(``channels.list``). One small, single-responsibility client; all the parsing
(ISO-8601 duration, thumbnail selection) lives on it as static helpers.

Failure is surfaced, never swallowed: a missing video (private / deleted /
invalid id) raises :class:`YouTubeVideoNotFoundError`, and any transport / HTTP
error raises :class:`YouTubeApiError` — the add endpoint maps both to a clear
client error rather than storing a metadata-less row. The channel-avatar fetch
is the one best-effort piece: if it fails the video is still added with an
empty ``channel_avatar_url`` (stored as-is; there is no serve-time backfill).
"""

from __future__ import annotations

import re

import httpx

from src.videos.schema.videos_schema import YouTubeVideoMetadata

# YouTube ids are 11 chars; a video has exactly one channel. One request each.
_VIDEOS_PARTS = "snippet,statistics,contentDetails"
_CHANNELS_PART = "snippet"
_HTTP_TIMEOUT_SECONDS = 30.0

# Best → worst thumbnail keys. We take the highest-res one the API returned.
_VIDEO_THUMBNAIL_PREFERENCE = ("maxres", "standard", "high", "medium", "default")
_AVATAR_THUMBNAIL_PREFERENCE = ("high", "medium", "default")

# A channel's public page from its id.
_CHANNEL_URL = "https://www.youtube.com/channel/{channel_id}"

# ISO-8601 video duration, e.g. PT1H2M3S / PT5M / P0D (live). Days are rare but
# possible for very long uploads, so they're parsed too.
_ISO_DURATION_RE = re.compile(
    r"^P(?:(?P<days>\d+)D)?T?(?:(?P<hours>\d+)H)?"
    r"(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?$"
)
_SECONDS_PER_DAY = 86400
_SECONDS_PER_HOUR = 3600
_SECONDS_PER_MINUTE = 60


class YouTubeMetadataError(Exception):
    """Base for any failure fetching a video's metadata."""


class YouTubeVideoNotFoundError(YouTubeMetadataError):
    """The id resolved to no video (private, deleted, or never existed)."""


class YouTubeApiError(YouTubeMetadataError):
    """The YouTube Data API call failed (transport / HTTP / quota)."""


# YouTubeVideoMetadata is defined in src.videos.schema.videos_schema and
# re-exported here for backwards-compatible imports.
__all__ = [
    "YouTubeVideoMetadata",
    "YouTubeMetadataError",
    "YouTubeVideoNotFoundError",
    "YouTubeApiError",
    "YouTubeMetadataClient",
]


class YouTubeMetadataClient:
    """Fetches one video's real metadata from the YouTube Data API."""

    def __init__(self, api_key: str, base_url: str) -> None:
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")

    async def fetch(self, video_id: str) -> YouTubeVideoMetadata:
        """Return the real metadata for ``video_id``.

        Raises:
            YouTubeVideoNotFoundError: the id resolved to no video.
            YouTubeApiError: the API call failed (transport / HTTP / quota).
        """
        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
            item = await self._get_video_item(client, video_id)
            snippet = item.get("snippet") or {}
            channel_id = snippet.get("channelId") or ""
            avatar = await self._get_channel_avatar(client, channel_id)

        view_count = self._to_int(
            (item.get("statistics") or {}).get("viewCount")
        )
        duration = self._parse_duration(
            (item.get("contentDetails") or {}).get("duration")
        )
        return YouTubeVideoMetadata(
            title=snippet.get("title") or "",
            channel_name=snippet.get("channelTitle") or "",
            channel_url=(
                _CHANNEL_URL.format(channel_id=channel_id) if channel_id else ""
            ),
            thumbnail_url=self._pick_thumbnail(
                snippet.get("thumbnails"), _VIDEO_THUMBNAIL_PREFERENCE
            ),
            channel_avatar_url=avatar,
            view_count=view_count,
            duration_seconds=duration,
        )

    async def _get_video_item(
        self, client: httpx.AsyncClient, video_id: str
    ) -> dict:
        """The single ``videos.list`` item for ``video_id`` (raises if absent)."""
        data = await self._get(
            client,
            "videos",
            {"part": _VIDEOS_PARTS, "id": video_id},
        )
        items = data.get("items") or []
        if not items:
            raise YouTubeVideoNotFoundError(
                f"no YouTube video for id {video_id!r}"
            )
        return items[0]

    async def _get_channel_avatar(
        self, client: httpx.AsyncClient, channel_id: str
    ) -> str:
        """The channel's avatar url — best-effort: any failure yields '' so the
        video still adds (the empty avatar is stored as-is; no serve-time
        backfill)."""
        if not channel_id:
            return ""
        try:
            data = await self._get(
                client,
                "channels",
                {"part": _CHANNELS_PART, "id": channel_id},
            )
        except YouTubeApiError:
            return ""
        items = data.get("items") or []
        if not items:
            return ""
        snippet = items[0].get("snippet") or {}
        return self._pick_thumbnail(
            snippet.get("thumbnails"), _AVATAR_THUMBNAIL_PREFERENCE
        )

    async def _get(
        self, client: httpx.AsyncClient, resource: str, params: dict
    ) -> dict:
        """One GET against the Data API (key appended); raises YouTubeApiError on
        any transport / HTTP failure."""
        try:
            response = await client.get(
                f"{self._base_url}/{resource}",
                params={**params, "key": self._api_key},
            )
            response.raise_for_status()
            return response.json()
        except httpx.HTTPError as exc:
            raise YouTubeApiError(
                f"YouTube Data API {resource} request failed: {exc}"
            ) from exc

    @staticmethod
    def _pick_thumbnail(
        thumbnails: object, preference: tuple[str, ...]
    ) -> str:
        """The highest-res thumbnail url present, by ``preference`` order; '' when
        none are available."""
        if not isinstance(thumbnails, dict):
            return ""
        for key in preference:
            entry = thumbnails.get(key)
            if isinstance(entry, dict) and entry.get("url"):
                return entry["url"]
        return ""

    @staticmethod
    def _to_int(value: object) -> int | None:
        """A numeric API string (e.g. ``viewCount``) as an int, or None."""
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _parse_duration(iso: object) -> int | None:
        """ISO-8601 duration (``PT1H2M3S``) → total seconds; None when absent or
        unparseable."""
        if not isinstance(iso, str) or not iso:
            return None
        match = _ISO_DURATION_RE.match(iso)
        if match is None:
            return None
        days = int(match.group("days") or 0)
        hours = int(match.group("hours") or 0)
        minutes = int(match.group("minutes") or 0)
        seconds = int(match.group("seconds") or 0)
        return (
            days * _SECONDS_PER_DAY
            + hours * _SECONDS_PER_HOUR
            + minutes * _SECONDS_PER_MINUTE
            + seconds
        )
