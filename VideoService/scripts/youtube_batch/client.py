"""Thin synchronous wrapper over the YouTube Data API v3.

One method per call we make: ``search`` (100 units), ``fetch_video_stats`` and
``fetch_channel_avatars`` (1 unit each, batched up to 50 ids). The client owns a
running quota estimate and a small retry-with-backoff for transient 5xx
failures; a ``403 quotaExceeded`` is terminal and surfaces a clear message.

Returns raw response dicts — parsing lives in ``transform.py`` so it stays
testable without the network.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Iterator, Sequence

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger(__name__)

# Per-call quota costs (YouTube Data API v3).
SEARCH_UNITS = 100
LIST_UNITS = 1
# videos.list / channels.list accept up to 50 ids per call.
MAX_IDS_PER_CALL = 50
# Backoff (seconds) for transient failures; len + 1 total attempts.
RETRY_BACKOFF_SECONDS = (5, 15, 30)
# HTTP statuses worth retrying (transient server-side).
RETRYABLE_STATUSES = frozenset({500, 502, 503, 504})


class QuotaExceededError(RuntimeError):
    """The daily YouTube Data API quota (10,000 units) is exhausted."""


class YouTubeClient:
    """Synchronous YouTube Data API client with quota accounting."""

    def __init__(self, api_key: str) -> None:
        # cache_discovery=False avoids a noisy warning + filesystem cache.
        self._youtube = build("youtube", "v3", developerKey=api_key,
                              cache_discovery=False)
        self._quota_units = 0

    @property
    def quota_units(self) -> int:
        """Total quota units spent so far this run."""
        return self._quota_units

    def search(self, query: str, *, max_results: int, lang: str) -> dict:
        """One ``search.list`` for videos. 100 units regardless of size."""
        self._quota_units += SEARCH_UNITS
        return self._execute(
            self._youtube.search().list(
                part="snippet",
                q=query,
                type="video",
                maxResults=max_results,
                relevanceLanguage=lang,
            ),
            what=f"search {query!r}",
        )

    def fetch_video_stats(self, video_ids: Sequence[str]) -> list[dict]:
        """``videos.list`` (statistics + contentDetails) for ids, batched 50 at
        a time. ``contentDetails`` rides along free — quota is per call, not per
        part — and carries the ISO 8601 ``duration``."""
        return self._batched(
            video_ids, part="statistics,contentDetails", what="video stats"
        )

    def fetch_channel_avatars(self, channel_ids: Sequence[str]) -> list[dict]:
        """``channels.list`` (snippet) for ids, batched 50 at a time."""
        return self._batched(channel_ids, part="snippet", what="channel avatars")

    def _batched(
        self, ids: Sequence[str], *, part: str, what: str
    ) -> list[dict]:
        """Run the relevant list() call over 50-id chunks; one unit per chunk.

        ``part`` selects the resource: a 'statistics'(+contentDetails) part ->
        videos.list, 'snippet' -> channels.list."""
        responses: list[dict] = []
        for chunk in _chunks(ids, MAX_IDS_PER_CALL):
            self._quota_units += LIST_UNITS
            collection = (
                self._youtube.videos()
                if "statistics" in part
                else self._youtube.channels()
            )
            # No maxResults here: videos.list / channels.list reject it when an
            # `id` filter is supplied (it's only valid with chart/mine listings).
            responses.append(
                self._execute(
                    collection.list(part=part, id=",".join(chunk)),
                    what=f"{what} ({len(chunk)} ids)",
                )
            )
        return responses

    @staticmethod
    def _execute(request: object, *, what: str) -> dict:
        """Execute a built request, retrying transient 5xx, failing fast on a
        quota error."""
        total = len(RETRY_BACKOFF_SECONDS) + 1
        for attempt in range(total):
            try:
                return request.execute()  # type: ignore[attr-defined]
            except HttpError as exc:
                status = exc.resp.status
                if status == 403 and "quota" in str(exc).lower():
                    raise QuotaExceededError(
                        "YouTube Data API daily quota exhausted (10,000 units). "
                        "Wait for the midnight-PT reset or request a quota "
                        "increase via Google's audit form."
                    ) from exc
                if status not in RETRYABLE_STATUSES or attempt == total - 1:
                    raise
                wait = RETRY_BACKOFF_SECONDS[attempt]
                logger.warning(
                    "%s failed (HTTP %s), attempt %d/%d; retrying in %ds",
                    what, status, attempt + 1, total, wait,
                )
                time.sleep(wait)
        raise RuntimeError("unreachable")  # loop always returns or raises


def _chunks(items: Sequence[str], size: int) -> Iterator[list[str]]:
    """Yield successive ``size``-length chunks of unique-order-preserving ids."""
    for start in range(0, len(items), size):
        yield list(items[start : start + size])
