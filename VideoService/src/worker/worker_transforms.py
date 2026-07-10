"""Pure transforms: YouTube Data API items → ``VideoOutput``.

No I/O and no API key needed here, so this is the unit-testable core of the
worker's scrape stage. One query's fetch is two API calls: ``search.list`` (id +
snippet) merged with ``videos.list`` (fuller snippet + statistics + duration).
This module pairs a query's search items with the by-id details and folds them
into deduped ``VideoOutput``s. Videos leave here untagged (``tag=None``, empty
``gym_type``) and WITHOUT a transcript — the enrich stage fills genre +
disciplines and fetches the transcript lazily (from Apify) only for the videos it
actually enriches.

A class-less concern module by design (pure functions) — the house exception to
"no loose module-level functions", exactly like the scan/roster mappers.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from schema.video_output import VideoOutput

WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
CHANNEL_URL = "https://www.youtube.com/channel/{channel_id}"
# ISO-8601 duration as YouTube reports it (``PT1H2M3S`` / ``PT5M30S`` / ``PT45S``,
# rarely with a leading day component) → seconds.
_ISO8601_DURATION = re.compile(
    r"^P(?:(?P<days>\d+)D)?"
    r"(?:T(?:(?P<hours>\d+)H)?(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?)?$"
)
# Thumbnail resolutions best → worst; the first present one is used.
_THUMBNAIL_PREFERENCE = ("maxres", "standard", "high", "medium", "default")


@dataclass(frozen=True)
class VideoHit:
    """One search-result item merged with its ``videos.list`` details, paired with
    the query that surfaced it and its rank within that query. The intermediate
    the dedup step folds over."""

    video_id: str
    url: str
    title: str
    description: str
    thumbnail_url: str
    channel_name: str
    channel_url: str
    channel_avatar_url: str
    view_count: int | None
    like_count: int | None
    duration_seconds: int | None
    query: str
    rank: int  # 0-based position in this query's results (lower = more relevant)


def youtube_item_id(item: dict) -> str:
    """The video id of a YouTube API item. ``search.list`` items nest it under
    ``id.videoId``; ``videos.list`` items carry a plain string ``id``. Empty when
    absent (a non-video search result)."""
    ident = item.get("id")
    if isinstance(ident, dict):
        return ident.get("videoId") or ""
    if isinstance(ident, str):
        return ident
    return ""


def _to_int(value: object) -> int | None:
    """Counts may be a numeric string (the API's shape), an int, or absent/hidden
    (likeCount is omitted when hidden) → None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        digits = value.replace(",", "").strip()
        return int(digits) if digits.isdigit() else None
    return None


def _parse_duration(value: object) -> int | None:
    """Runtime in seconds from an ISO-8601 duration string (``PT#H#M#S``).
    Anything unparseable or zero (e.g. a live broadcast's ``P0D``/``PT0S``) →
    None."""
    if not isinstance(value, str):
        return None
    match = _ISO8601_DURATION.match(value.strip())
    if not match:
        return None
    parts = {k: int(v) if v else 0 for k, v in match.groupdict().items()}
    total = (
        parts["days"] * 86400
        + parts["hours"] * 3600
        + parts["minutes"] * 60
        + parts["seconds"]
    )
    return total or None


def _best_thumbnail(thumbnails: object) -> str:
    """The highest-resolution thumbnail URL from a snippet's ``thumbnails`` map,
    or empty string when none is present."""
    if not isinstance(thumbnails, dict):
        return ""
    for key in _THUMBNAIL_PREFERENCE:
        entry = thumbnails.get(key)
        if isinstance(entry, dict) and entry.get("url"):
            return str(entry["url"])
    return ""


def parse_youtube_items(
    search_items: Sequence[dict],
    details_by_id: Mapping[str, dict],
    query: str,
) -> list[VideoHit]:
    """Pull the modelled fields out of a query's ``search.list`` items, enriched
    by the matching ``videos.list`` details, pairing every video with the query
    that produced it. The ``videos.list`` snippet is preferred (its title +
    description are un-truncated); non-video / id-less items are skipped; rank is
    the contiguous position among the videos kept."""
    hits: list[VideoHit] = []
    for item in search_items:
        video_id = youtube_item_id(item)
        if not video_id:
            continue
        search_snippet = item.get("snippet") or {}
        detail = details_by_id.get(video_id) or {}
        detail_snippet = detail.get("snippet") or {}
        snippet = detail_snippet or search_snippet
        stats = detail.get("statistics") or {}
        content = detail.get("contentDetails") or {}
        channel_id = snippet.get("channelId") or search_snippet.get("channelId") or ""
        hits.append(
            VideoHit(
                video_id=video_id,
                url=WATCH_URL.format(video_id=video_id),
                title=snippet.get("title") or search_snippet.get("title") or "",
                description=snippet.get("description") or "",
                thumbnail_url=_best_thumbnail(
                    snippet.get("thumbnails") or search_snippet.get("thumbnails")
                ),
                channel_name=(
                    snippet.get("channelTitle")
                    or search_snippet.get("channelTitle")
                    or ""
                ),
                channel_url=(
                    CHANNEL_URL.format(channel_id=channel_id) if channel_id else ""
                ),
                channel_avatar_url="",  # the API's snippet carries no avatar
                view_count=_to_int(stats.get("viewCount")),
                like_count=_to_int(stats.get("likeCount")),
                duration_seconds=_parse_duration(content.get("duration")),
                query=query,
                rank=len(hits),
            )
        )
    return hits


def build_outputs(hits: Sequence[VideoHit]) -> list[VideoOutput]:
    """De-dup hits by video id into ``VideoOutput``s. First hit wins for content;
    the queries that surfaced a video are merged and the best (lowest) rank kept.
    Videos leave here untagged (``tag=None``, empty ``gym_type``) and without a
    transcript — the enrich stage fills both."""
    first: dict[str, VideoHit] = {}
    merged_queries: dict[str, dict[str, None]] = {}
    best_rank: dict[str, int] = {}
    for hit in hits:
        if hit.video_id not in first:
            first[hit.video_id] = hit
            merged_queries[hit.video_id] = {}
            best_rank[hit.video_id] = hit.rank
        merged_queries[hit.video_id].setdefault(hit.query, None)
        best_rank[hit.video_id] = min(best_rank[hit.video_id], hit.rank)

    outputs: list[VideoOutput] = []
    for video_id, hit in first.items():
        outputs.append(
            VideoOutput(
                url=hit.url,
                title=hit.title,
                description=hit.description,
                thumbnail_url=hit.thumbnail_url,
                channel_name=hit.channel_name,
                channel_url=hit.channel_url,
                channel_avatar_url=hit.channel_avatar_url,
                view_count=hit.view_count,
                like_count=hit.like_count,
                duration_seconds=hit.duration_seconds,
                source_queries=list(merged_queries[video_id]),
                relevance_index=best_rank[video_id],
                transcript=None,
            )
        )
    return outputs
