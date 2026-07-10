"""Async Apify client — YouTube transcripts ONLY, fetched lazily at enrich.

Discovery + metadata come from the official YouTube Data API
(``worker_youtube.py``); this actor is used solely to fetch transcripts for the
videos the enrich stage is about to classify, because the free
``youtube-transcript-api`` PyPI lib is IP-blocked from cloud hosts.

Fetches are **BATCHED**: one actor run takes a LIST of watch urls
(``supreme_coder/youtube-transcript-scraper``) and returns one dataset item per
input url. Each success item carries a cue list under ``transcript``
(``{text, start, duration}``) which is joined and cleaned into plain text; an
error item (no captions / unavailable) carries an ``error`` and is mapped to
None. Items are matched back to their video by the ``?v=<id>`` in ``inputUrl``.
Any miss/failure/timeout returns None for that video and enrich degrades to its
no-transcript placeholder — a transcript miss never aborts a run or strikes a
video. Uses the native ``ApifyClientAsync`` so the call is awaitable under the
enrich semaphore.

The batched ``.call()`` is bounded two ways (the un-bounded default waits
indefinitely and froze the worker): ``wait_duration`` caps the server-side wait,
and ``asyncio.wait_for`` wraps the whole ``fetch_batch`` with a longer client-side
deadline — on expiry the batch degrades to all-None (everyone gets the
placeholder). Both timeouts are LONG/conservative Settings knobs because one
batched run of up to ~64 videos can take several minutes.

See: apify.com/supreme_coder/youtube-transcript-scraper
($0.0005 / transcript + $0.001 / actor start).
"""

from __future__ import annotations

import asyncio
import html
import logging
import re
import urllib.parse
from collections.abc import Sequence
from datetime import timedelta

from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

# The batched transcript actor and the watch-URL shape are properties of this
# integration, not config.
ACTOR_ID = "supreme_coder/youtube-transcript-scraper"
WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
# Keys under which a dataset entry may nest its cue list, if it wraps them rather
# than being a single cue itself. ``transcript`` is the batched actor's success
# key; the rest are tolerated legacy/alternate shapes.
_CUE_LIST_KEYS = ("transcript", "data", "captions", "segments")
# An SRT cue index / timestamp line, stripped defensively in case a cue's text
# ever carries srt scaffolding.
_SRT_TIMECODE = re.compile(r"^\d+$|-->")


class WorkerTranscriptClient:
    """Fetches transcripts for a batch of videos via one Apify actor run."""

    def __init__(self, token: str) -> None:
        # Imported lazily so the module (and its testable callers) load without
        # the optional dependency; only an actual fetch needs it.
        from apify_client import ApifyClientAsync

        self._client = ApifyClientAsync(
            token, max_retries=settings.apify_max_retries
        )

    async def fetch_batch(self, video_ids: list[str]) -> dict[str, str | None]:
        """Run the actor ONCE for the whole list and return
        ``{video_id: cleaned_transcript_or_None}`` — one entry per input id.

        An empty list is a no-op (no actor run, no start cost). Every input id is
        seeded to None so a video the actor drops (or an error item) still maps to
        None → the enrich placeholder, never a strike. Any failure or a
        ``apify_fetch_deadline_seconds`` timeout returns all-None for the batch."""
        result: dict[str, str | None] = {vid: None for vid in video_ids}
        if not video_ids:
            return result
        try:
            items = await asyncio.wait_for(
                self._run_batch(video_ids),
                timeout=settings.apify_fetch_deadline_seconds,
            )
        except TimeoutError:
            logger.warning(
                "transcript batch timed out after %ds for %d video(s) — "
                "degrading all to the placeholder",
                settings.apify_fetch_deadline_seconds,
                len(video_ids),
            )
            return result
        except Exception as exc:  # noqa: BLE001 - a transcript miss never aborts
            logger.warning(
                "transcript batch failed for %d video(s): %s", len(video_ids), exc
            )
            return result
        for item in items:
            if not isinstance(item, dict):
                continue
            video_id = _video_id_from_input_url(item)
            if video_id is None or video_id not in result:
                continue
            result[video_id] = _transcript_from_item(item)
        return result

    async def _run_batch(self, video_ids: list[str]) -> list[object]:
        """One bounded actor run over ``video_ids`` → its dataset items. The
        ``wait_duration`` bounds the server-side wait (default is indefinite)."""
        run = await self._client.actor(ACTOR_ID).call(
            run_input={
                "urls": [
                    {"url": WATCH_URL.format(video_id=vid)} for vid in video_ids
                ],
                "outputFormat": "json",
            },
            wait_duration=timedelta(seconds=settings.apify_run_wait_seconds),
        )
        dataset_id = (
            run.get("defaultDatasetId")
            if isinstance(run, dict)
            else getattr(run, "default_dataset_id", None)
        )
        if not dataset_id:
            return []
        page = await self._client.dataset(dataset_id).list_items()
        return list(page.items)


def _video_id_from_input_url(item: dict) -> str | None:
    """The ``?v=<id>`` from a batch item's ``inputUrl`` (present on both success
    and error items), or None when it can't be parsed."""
    url = item.get("inputUrl")
    if not isinstance(url, str):
        return None
    values = urllib.parse.parse_qs(urllib.parse.urlparse(url).query).get("v")
    return values[0] if values else None


def _transcript_from_item(item: dict) -> str | None:
    """One batch item's transcript as cleaned plain text, or None. A success item
    nests a cue list (``{text, start, duration}``) under ``transcript``; an error
    item (no captions / unavailable) has no cue list → None."""
    cues = item.get("transcript")
    if not isinstance(cues, list):
        return None
    return transcript_from_items(cues)


def transcript_from_items(items: Sequence[object]) -> str | None:
    """Join a transcript run's cue items into cleaned plain text, or None when
    there is nothing usable. Reads only each cue's ``text`` (the ``start`` /
    ``duration`` fields are ignored)."""
    texts: list[str] = []
    for item in items:
        if isinstance(item, dict):
            texts.extend(_texts_from_entry(item))
        elif isinstance(item, str):
            texts.append(item)
    return _clean(" ".join(t for t in texts if t and t.strip()))


def _texts_from_entry(entry: dict) -> list[str]:
    """Cue text from one entry — a single cue (``{text}``) or a wrapper that nests
    the cue list under a transcript/data/captions key."""
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
