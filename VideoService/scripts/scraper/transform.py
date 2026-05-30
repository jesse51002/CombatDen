"""Pure transforms: raw ``streamers/youtube-scraper`` dataset items -> ``VideoOutput``s.

No I/O and no Apify token needed here, so this is the unit-testable core. One
Apify run per query returns fully-enriched items (metadata + channel avatar +
inline subtitles), so unlike the YouTube Data API path there is no separate
stats/avatar/transcript enrichment — every field comes from the one item.

Tags are *not* assigned here: a video leaves the search untagged. The pool
tagging pass (``scripts/classify``) decides each video's genre + disciplines from
its real content; the per-gym scan decides approval.
"""

from __future__ import annotations

import html
import re
from collections.abc import Sequence
from dataclasses import dataclass

from schema.video_output import VideoOutput
from src.shared.util.video_id import video_id_from_url

WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
# "1:02:03" / "5:30" / "45" -> seconds. The actor reports duration as a clock
# string (or sometimes an int of seconds); both are handled, bad/absent -> None.
_CLOCK = re.compile(r"^\d+(?::\d{1,2})*$")
# An SRT cue index/timestamp line, so a defensively-stripped transcript reads
# clean even if the actor ever returns srt where we asked for plaintext.
_SRT_TIMECODE = re.compile(r"^\d+$|-->")


@dataclass(frozen=True)
class ApifyHit:
    """One search-result item, paired with the query that surfaced it and its
    rank within that query. The intermediate the dedup step folds over."""

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
    transcript: str | None
    query: str
    rank: int  # 0-based position in this query's results (lower = more relevant)


def _to_int(value: object) -> int | None:
    """Counts may be int, numeric string, or absent/hidden -> None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        digits = value.replace(",", "").strip()
        return int(digits) if digits.isdigit() else None
    return None


def _parse_duration(value: object) -> int | None:
    """Runtime in seconds from an int (already seconds) or a clock string
    (``H:MM:SS`` / ``M:SS`` / ``SS``). Anything else -> None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value or None
    if isinstance(value, str) and _CLOCK.match(value.strip()):
        total = 0
        for part in value.strip().split(":"):
            total = total * 60 + int(part)
        return total or None
    return None


def _extract_transcript(item: dict) -> str | None:
    """The plain-text transcript from an item's ``subtitles`` array, or None.

    We request ``subtitlesFormat=plaintext``, so each entry's ``srt`` field holds
    plain text; we still defensively strip SRT cue numbers / timecodes in case an
    srt-shaped payload comes back, and unescape HTML entities the captions carry."""
    subtitles = item.get("subtitles")
    if not isinstance(subtitles, list):
        return None
    for entry in subtitles:
        if not isinstance(entry, dict):
            continue
        text = entry.get("srt") or entry.get("text") or entry.get("plaintext")
        if isinstance(text, str) and text.strip():
            lines = [
                ln
                for ln in text.splitlines()
                if ln.strip() and not _SRT_TIMECODE.search(ln.strip())
            ]
            cleaned = html.unescape(" ".join(lines).strip())
            if cleaned:
                return cleaned
    return None


def parse_search_items(items: Sequence[dict], query: str) -> list[ApifyHit]:
    """Pull the modelled fields out of one run's dataset items, pairing every
    video with the query that produced it. Non-video / id-less items are skipped;
    rank is the contiguous position among the videos kept."""
    hits: list[ApifyHit] = []
    for item in items:
        url = item.get("url") or ""
        video_id = item.get("id") or video_id_from_url(url)
        if not video_id:
            continue
        hits.append(
            ApifyHit(
                video_id=video_id,
                url=url or WATCH_URL.format(video_id=video_id),
                title=item.get("title") or "",
                description=item.get("text") or item.get("description") or "",
                thumbnail_url=item.get("thumbnailUrl") or "",
                channel_name=item.get("channelName") or "",
                channel_url=item.get("channelUrl") or "",
                channel_avatar_url=item.get("channelAvatarUrl") or "",
                view_count=_to_int(item.get("viewCount")),
                like_count=_to_int(item.get("likes")),
                duration_seconds=_parse_duration(item.get("duration")),
                transcript=_extract_transcript(item),
                query=query,
                rank=len(hits),
            )
        )
    return hits


def build_outputs(hits: Sequence[ApifyHit]) -> list[VideoOutput]:
    """De-dup hits by video id into ``VideoOutput``s. First hit wins for content
    (incl. transcript); the queries that surfaced a video are merged and the best
    (lowest) rank kept. Videos leave here untagged (``tag=None``, empty
    ``gym_type``); the pool tagging pass fills those."""
    first: dict[str, ApifyHit] = {}
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
                transcript=hit.transcript,
            )
        )
    return outputs
