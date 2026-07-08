"""Async Apify client — YouTube transcripts ONLY, fetched lazily at enrich.

Discovery + metadata come from the official YouTube Data API
(``worker_youtube.py``); this actor is used solely to fetch a transcript for a
video the enrich stage is about to classify, because the free
``youtube-transcript-api`` PyPI lib is IP-blocked from cloud hosts. One actor run
per video (the actor takes a single ``videoUrl``); the run returns caption cues
(``{start, dur, text}``) which are joined and cleaned into plain text. Any miss
or failure returns None and enrich degrades to its no-transcript placeholder — a
transcript miss never aborts a run. Uses the native ``ApifyClientAsync`` so the
call is awaitable under the enrich semaphore.

See: apify.com/pintostudio/youtube-transcript-scraper ($10 / 1,000 results).
"""

from __future__ import annotations

import html
import logging
import re
from collections.abc import Sequence

logger = logging.getLogger(__name__)

# The transcript-only actor and the watch-URL shape are properties of this
# integration, not config.
ACTOR_ID = "pintostudio/youtube-transcript-scraper"
WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
# Keys under which a dataset entry may nest its cue list, if it wraps them rather
# than being a single cue itself.
_CUE_LIST_KEYS = ("transcript", "data", "captions", "segments")
# An SRT cue index / timestamp line, stripped defensively in case a cue's text
# ever carries srt scaffolding.
_SRT_TIMECODE = re.compile(r"^\d+$|-->")


class WorkerTranscriptClient:
    """Fetches a single video's transcript via the Apify transcript actor."""

    def __init__(self, token: str) -> None:
        # Imported lazily so the module (and its testable callers) load without
        # the optional dependency; only an actual fetch needs it.
        from apify_client import ApifyClientAsync

        self._client = ApifyClientAsync(token)

    async def fetch(self, video_id: str, *, language: str) -> str | None:
        """Run the actor for one video and return its transcript as plain text, or
        None on any miss/failure (enrich degrades to the placeholder)."""
        try:
            run = await self._client.actor(ACTOR_ID).call(
                run_input={
                    "videoUrl": WATCH_URL.format(video_id=video_id),
                    "targetLanguage": language,
                }
            )
            dataset_id = (
                run.get("defaultDatasetId")
                if isinstance(run, dict)
                else getattr(run, "default_dataset_id", None)
            )
            if not dataset_id:
                return None
            page = await self._client.dataset(dataset_id).list_items()
            items = list(page.items)
        except Exception as exc:  # noqa: BLE001 - a transcript miss never aborts
            logger.warning("transcript fetch failed for %s: %s", video_id, exc)
            return None
        return transcript_from_items(items)


def transcript_from_items(items: Sequence[object]) -> str | None:
    """Join an Apify transcript run's cue items into cleaned plain text, or None
    when there is nothing usable."""
    texts: list[str] = []
    for item in items:
        if isinstance(item, dict):
            texts.extend(_texts_from_entry(item))
        elif isinstance(item, str):
            texts.append(item)
    return _clean(" ".join(t for t in texts if t and t.strip()))


def _texts_from_entry(entry: dict) -> list[str]:
    """Cue text from one dataset entry — a single cue (``{text}``) or a wrapper
    that nests the cue list under a data/transcript/captions key."""
    text = entry.get("text")
    if isinstance(text, str):
        return [text]
    for key in _CUE_LIST_KEYS:
        nested = entry.get(key)
        if isinstance(nested, list):
            return [
                cue["text"]
                for cue in nested
                if isinstance(cue, dict) and isinstance(cue.get("text"), str)
            ]
    return []


def _clean(text: str) -> str | None:
    """Strip srt cue numbers / timecodes defensively, unescape HTML entities the
    captions carry. Empty result → None."""
    if not text.strip():
        return None
    lines = [
        ln
        for ln in text.splitlines()
        if ln.strip() and not _SRT_TIMECODE.search(ln.strip())
    ]
    cleaned = html.unescape(" ".join(lines).strip())
    return cleaned or None
