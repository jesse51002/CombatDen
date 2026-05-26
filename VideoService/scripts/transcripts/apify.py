"""Thin wrapper over the Apify YouTube transcript scraper.

One async actor run handles a whole batch of URLs: we submit them all at once as
``urls: [{"url": ...}]`` request objects, ``.call()`` blocks until the run
finishes (Apify does the polling) and returns a ``Run`` whose
``default_dataset_id`` holds the results. Each dataset item carries the
``inputUrl`` we sent plus a ``transcript`` (a plain string under
``outputFormat="text"``); failed videos (no captions / age-restricted) come back
without one. Results are keyed by **video id** parsed from ``inputUrl`` so they
survive any URL normalisation.

See: apify.com/supreme_coder/youtube-transcript-scraper
"""

from __future__ import annotations

import html
import logging
from dataclasses import dataclass, field

from apify_client import ApifyClient

from src.shared.util.video_id import video_id_from_url

logger = logging.getLogger(__name__)

# The actor and output format are properties of this integration, not config.
ACTOR_ID = "supreme_coder/youtube-transcript-scraper"
OUTPUT_FORMAT = "text"  # plain-text transcript (vs json/srt/vtt)
# $0.0005 per transcript scraped (attempted), live as of 2026-05; re-verify on
# the actor page before relying on it for a large run.
USD_PER_TRANSCRIPT = 0.0005


@dataclass(frozen=True)
class TranscriptResults:
    """One Apify run's outcome, keyed by video id: the transcripts we got, and
    the reason (provider error code / ``no captions``) for the ones we didn't."""

    transcripts: dict[str, str] = field(default_factory=dict)
    errors: dict[str, str] = field(default_factory=dict)


def _extract_transcript(item: dict) -> str | None:
    """The transcript text from one dataset item, or None on a failed item.

    With ``outputFormat="text"`` the ``transcript`` is a plain string; we also
    tolerate the json shape (a list of ``{text, start, duration}`` segments) by
    joining the segment text, so a format change doesn't silently drop data.
    HTML entities (``&#39;`` etc.) the captions carry are unescaped."""
    transcript = item.get("transcript")
    if isinstance(transcript, str) and transcript.strip():
        return html.unescape(transcript.strip())
    if isinstance(transcript, list):
        joined = " ".join(
            seg["text"] for seg in transcript if isinstance(seg, dict) and seg.get("text")
        ).strip()
        return html.unescape(joined) or None
    return None


def fetch_transcripts(token: str, urls: list[str]) -> TranscriptResults:
    """Fetch transcripts for ``urls`` in one Apify run. Returns the transcripts
    we got and, for the rest, the reason the provider gave (so the caller can
    record *why* a video has no transcript)."""
    results = TranscriptResults()
    if not urls:
        return results
    client = ApifyClient(token)
    logger.info("submitting %d urls to Apify actor %s", len(urls), ACTOR_ID)
    run = client.actor(ACTOR_ID).call(
        run_input={"urls": [{"url": u} for u in urls], "outputFormat": OUTPUT_FORMAT}
    )
    dataset_id = getattr(run, "default_dataset_id", None) if run else None
    if not dataset_id:
        raise RuntimeError("Apify run did not return a dataset id")

    for item in client.dataset(dataset_id).iterate_items():
        video_id = video_id_from_url(item.get("inputUrl", ""))
        if not video_id:
            logger.warning("Apify item with no resolvable video id: %r", item.get("inputUrl"))
            continue
        text = _extract_transcript(item)
        if text:
            results.transcripts[video_id] = text
        else:
            reason = item.get("errorCode") or item.get("error") or "no captions"
            results.errors[video_id] = str(reason)
            logger.warning("no transcript for %s (%s)", video_id, reason)
    return results
