"""Pure transforms: raw YouTube Data API response dicts -> ``VideoOutput``s.

No I/O and no API key needed here, so this is the unit-testable core. Every
read of a raw response uses tolerant ``.get()`` access and pulls only the
fields we model, so new or renamed YouTube fields are simply ignored rather
than crashing the run.

Tags are *not* assigned here: a search no longer carries genre tags, so a
video leaves the batch untagged. The separate classification pass
(``scripts/classify``) decides each video's genre from its real content.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

from schema.video_output import VideoOutput

WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
CHANNEL_URL = "https://www.youtube.com/channel/{channel_id}"
# Highest resolution first; we take the first key a video actually has.
THUMBNAIL_PREFERENCE = ("maxres", "standard", "high", "medium", "default")
# ISO 8601 duration as YouTube reports it: PT#H#M#S, with an optional leading
# day part (P#DT...). Every component is optional (a 45s clip is just "PT45S").
_ISO8601_DURATION = re.compile(
    r"^P(?:(?P<days>\d+)D)?T(?:(?P<hours>\d+)H)?"
    r"(?:(?P<minutes>\d+)M)?(?:(?P<seconds>\d+)S)?$"
)


@dataclass(frozen=True)
class SearchHit:
    """One ``search.list`` result, paired with the query that surfaced it. The
    intermediate the dedup step folds over."""

    video_id: str
    channel_id: str
    title: str
    description: str
    thumbnail_url: str
    channel_name: str
    query: str
    rank: int  # 0-based position in this query's results (lower = more relevant)


@dataclass(frozen=True)
class VideoStats:
    """The per-video facts ``videos.list`` returns: counts (hidden -> None) and
    runtime in seconds (no duration reported -> None)."""

    view_count: int | None
    like_count: int | None
    duration_seconds: int | None


def _best_thumbnail(thumbnails: dict) -> str:
    """Highest-resolution thumbnail URL available, or '' if none."""
    for key in THUMBNAIL_PREFERENCE:
        entry = thumbnails.get(key)
        if entry and entry.get("url"):
            return entry["url"]
    return ""


def _to_int(value: object) -> int | None:
    """YouTube statistics are strings; absent/hidden -> None."""
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _parse_iso8601_duration(value: object) -> int | None:
    """ISO 8601 duration (e.g. ``PT5M30S``) -> total seconds; bad/absent -> None.

    Tolerant by design: a shape we don't recognize (a live broadcast's ``P0D``,
    or any future quirk) yields ``None`` rather than crashing the batch."""
    if not isinstance(value, str):
        return None
    match = _ISO8601_DURATION.match(value)
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


def parse_search_response(raw: dict, query: str) -> list[SearchHit]:
    """Pull the modelled fields out of one ``search.list`` response, pairing
    every hit with the query that produced it."""
    hits: list[SearchHit] = []
    for item in raw.get("items", []):
        video_id = (item.get("id") or {}).get("videoId")
        if not video_id:
            continue  # not a video result (channel/playlist) — skip
        snippet = item.get("snippet") or {}
        channel_id = snippet.get("channelId", "")
        hits.append(
            SearchHit(
                video_id=video_id,
                channel_id=channel_id,
                title=snippet.get("title", ""),
                description=snippet.get("description", ""),
                thumbnail_url=_best_thumbnail(snippet.get("thumbnails") or {}),
                channel_name=snippet.get("channelTitle", ""),
                query=query,
                # Contiguous rank among *video* hits (skipped non-videos don't
                # leave gaps): the Nth video this query returned.
                rank=len(hits),
            )
        )
    return hits


def parse_channel_avatars(raw: dict) -> dict[str, str]:
    """``channels.list`` response -> {channel_id: avatar_url}."""
    avatars: dict[str, str] = {}
    for item in raw.get("items", []):
        channel_id = item.get("id")
        if not channel_id:
            continue
        thumbnails = (item.get("snippet") or {}).get("thumbnails") or {}
        avatars[channel_id] = _best_thumbnail(thumbnails)
    return avatars


def parse_video_stats(raw: dict) -> dict[str, VideoStats]:
    """``videos.list`` (statistics + contentDetails) response ->
    {video_id: VideoStats}."""
    stats: dict[str, VideoStats] = {}
    for item in raw.get("items", []):
        video_id = item.get("id")
        if not video_id:
            continue
        statistics = item.get("statistics") or {}
        content_details = item.get("contentDetails") or {}
        stats[video_id] = VideoStats(
            view_count=_to_int(statistics.get("viewCount")),
            like_count=_to_int(statistics.get("likeCount")),
            duration_seconds=_parse_iso8601_duration(
                content_details.get("duration")
            ),
        )
    return stats


def build_outputs(
    hits: Sequence[SearchHit],
    avatars: dict[str, str],
    stats: dict[str, VideoStats],
) -> list[VideoOutput]:
    """De-dup hits by video id and enrich each with its avatar, view/like
    counts, and runtime. Videos leave here untagged (``tag=None``); the
    classification pass fills the genre and the keep/drop verdict."""
    # video_id -> first hit seen, plus a running ordered set of the queries that
    # surfaced it and the best (lowest) rank across them.
    first: dict[str, SearchHit] = {}
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
        stat = stats.get(video_id)
        outputs.append(
            VideoOutput(
                url=WATCH_URL.format(video_id=video_id),
                title=hit.title,
                description=hit.description,
                thumbnail_url=hit.thumbnail_url,
                channel_name=hit.channel_name,
                channel_url=CHANNEL_URL.format(channel_id=hit.channel_id),
                channel_avatar_url=avatars.get(hit.channel_id, ""),
                view_count=stat.view_count if stat else None,
                like_count=stat.like_count if stat else None,
                duration_seconds=stat.duration_seconds if stat else None,
                source_queries=list(merged_queries[video_id]),
                relevance_index=best_rank[video_id],
            )
        )
    return outputs
