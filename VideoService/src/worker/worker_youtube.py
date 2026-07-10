"""Async YouTube Data API v3 client — discovery + metadata for the scrape stage.

Two calls compose one query's fetch: ``search.list`` surfaces the video ids +
snippet for a query (100 quota units), then ``videos.list`` batches those ids for
``statistics`` (view/like counts) and ``contentDetails.duration`` (1 unit per
call, ids batched ≤50). A search item's snippet has no channel avatar, so that
field is left empty (the avatar backfill was a read-path concern, since removed).

Uses ``httpx`` (async) rather than the sync ``google-api-python-client`` so the
whole call overlaps under the scrape semaphore — the worker's no-blocking-I/O
rule. The API is free within the daily quota (10,000 units/day by default; a
quota increase is a free Google Cloud request). A quota-exhausted (HTTP 403) or
any other HTTP error raises, and the scraper drops just that query.

See: developers.google.com/youtube/v3/docs/search/list + /videos/list
"""

from __future__ import annotations

import logging

import httpx

from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

SEARCH_URL = "https://www.googleapis.com/youtube/v3/search"
VIDEOS_URL = "https://www.googleapis.com/youtube/v3/videos"
# The API caps a single search / videos page (and a videos.list id batch) at 50.
MAX_PAGE_SIZE = 50


class WorkerYouTubeClient:
    """Searches YouTube + fetches video details via the official Data API v3."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key
        # One reusable async client for the worker's lifetime; httpx clients are
        # safe under the scrape concurrency gate and pool their connections.
        self._client = httpx.AsyncClient(
            timeout=settings.worker_youtube_timeout_seconds
        )

    async def search(
        self, query: str, *, max_results: int, language: str
    ) -> list[dict]:
        """``search.list`` for one query → its result items (id + snippet). Each
        call costs 100 quota units."""
        logger.info("YouTube search %r (max %d)", query, max_results)
        data = await self._get(
            SEARCH_URL,
            {
                "part": "snippet",
                "q": query,
                "type": "video",
                "order": "relevance",
                "maxResults": min(max_results, MAX_PAGE_SIZE),
                "relevanceLanguage": language,
                "key": self._api_key,
            },
        )
        return list(data.get("items", []))

    async def list_videos(self, video_ids: list[str]) -> list[dict]:
        """``videos.list`` for the given ids (batched ≤50) → each id's snippet +
        statistics + contentDetails. 1 quota unit per batch call."""
        items: list[dict] = []
        for start in range(0, len(video_ids), MAX_PAGE_SIZE):
            batch = video_ids[start : start + MAX_PAGE_SIZE]
            data = await self._get(
                VIDEOS_URL,
                {
                    "part": "snippet,statistics,contentDetails",
                    "id": ",".join(batch),
                    "maxResults": MAX_PAGE_SIZE,
                    "key": self._api_key,
                },
            )
            items.extend(data.get("items", []))
        return items

    async def _get(self, url: str, params: dict) -> dict:
        """One GET; a non-2xx status (incl. 403 quotaExceeded) raises for the
        caller to drop this query."""
        resp = await self._client.get(url, params=params)
        resp.raise_for_status()
        return resp.json()
