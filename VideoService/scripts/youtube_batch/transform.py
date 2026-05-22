"""Pure transforms: raw YouTube Data API response dicts -> ``VideoOutput``s.

No I/O and no API key needed here, so this is the unit-testable core. Every
read of a raw response uses tolerant ``.get()`` access and pulls only the
fields we model, so new or renamed YouTube fields are simply ignored rather
than crashing the run.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass

from schema.video_output import VideoOutput
from schema.video_type import VideoType

WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
CHANNEL_URL = "https://www.youtube.com/channel/{channel_id}"
# Highest resolution first; we take the first key a video actually has.
THUMBNAIL_PREFERENCE = ("maxres", "standard", "high", "medium", "default")


@dataclass(frozen=True)
class SearchHit:
    """One ``search.list`` result, paired with the query that surfaced it and
    that query's tags. The intermediate the dedup step folds over."""

    video_id: str
    channel_id: str
    title: str
    description: str
    thumbnail_url: str
    channel_name: str
    query: str
    tags: tuple[VideoType, ...]
    rank: int  # 0-based position in this query's results (lower = more relevant)


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


def parse_search_response(
    raw: dict, query: str, tags: Sequence[VideoType]
) -> list[SearchHit]:
    """Pull the modelled fields out of one ``search.list`` response, tagging
    every hit with the query that produced it and that query's genres."""
    hits: list[SearchHit] = []
    tag_tuple = tuple(tags)
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
                tags=tag_tuple,
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


def parse_video_stats(raw: dict) -> dict[str, tuple[int | None, int | None]]:
    """``videos.list`` response -> {video_id: (view_count, like_count)}."""
    stats: dict[str, tuple[int | None, int | None]] = {}
    for item in raw.get("items", []):
        video_id = item.get("id")
        if not video_id:
            continue
        statistics = item.get("statistics") or {}
        stats[video_id] = (
            _to_int(statistics.get("viewCount")),
            _to_int(statistics.get("likeCount")),
        )
    return stats


def build_outputs(
    hits: Sequence[SearchHit],
    avatars: dict[str, str],
    stats: dict[str, tuple[int | None, int | None]],
) -> list[VideoOutput]:
    """De-dup hits by video id (unioning tags in first-seen order) and enrich
    each with its avatar and view/like counts."""
    # video_id -> first hit seen, plus running ordered sets of tags and queries
    # and the best (lowest) rank across every query that surfaced it.
    first: dict[str, SearchHit] = {}
    merged_tags: dict[str, dict[VideoType, None]] = {}
    merged_queries: dict[str, dict[str, None]] = {}
    best_rank: dict[str, int] = {}
    for hit in hits:
        if hit.video_id not in first:
            first[hit.video_id] = hit
            merged_tags[hit.video_id] = {}
            merged_queries[hit.video_id] = {}
            best_rank[hit.video_id] = hit.rank
        for tag in hit.tags:
            merged_tags[hit.video_id].setdefault(tag, None)
        merged_queries[hit.video_id].setdefault(hit.query, None)
        best_rank[hit.video_id] = min(best_rank[hit.video_id], hit.rank)

    outputs: list[VideoOutput] = []
    for video_id, hit in first.items():
        view_count, like_count = stats.get(video_id, (None, None))
        outputs.append(
            VideoOutput(
                url=WATCH_URL.format(video_id=video_id),
                title=hit.title,
                description=hit.description,
                thumbnail_url=hit.thumbnail_url,
                channel_name=hit.channel_name,
                channel_url=CHANNEL_URL.format(channel_id=hit.channel_id),
                channel_avatar_url=avatars.get(hit.channel_id, ""),
                view_count=view_count,
                like_count=like_count,
                tags=list(merged_tags[video_id]),
                source_queries=list(merged_queries[video_id]),
                relevance_index=best_rank[video_id],
            )
        )
    return outputs
