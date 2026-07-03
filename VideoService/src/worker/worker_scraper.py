"""Stage 2 — scrape the spec's queries into the shared pool.

One Apify actor run per query (concurrent under a semaphore); a failed query is
logged and dropped, never aborting the run (partial scrape is fine). Results are
transformed by the pure ``worker_transforms`` and merge-upserted into ``video``:
new videos land untagged, existing videos keep their content (never wiped with
NULLs) and gain the surfacing query. Reports the Apify spend and new/updated split.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from pathlib import Path

from schema.video_output import VideoOutput
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.util.video_id import video_id_from_url
from src.worker.worker_apify import WorkerApifyClient
from src.worker.worker_config import settings
from src.worker.worker_spec import SpecData
from src.worker.worker_transforms import parse_search_items, build_outputs

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
SCRAPE_LANGUAGE = "en"


@dataclass(frozen=True)
class ScrapeResult:
    """What one scrape did: spend + how much of the pool it touched."""

    apify_usd: float
    results_fetched: int  # raw video items returned across all queries
    new_count: int
    updated_count: int


class WorkerScraper:
    """Runs the spec's queries through Apify and merges results into the pool."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        apify_client: WorkerApifyClient,
    ) -> None:
        self._db = db_pool
        self._apify = apify_client

    async def scrape(self, spec: SpecData) -> ScrapeResult:
        """Fetch every spec query and merge-upsert the results into ``video``."""
        queries = spec.queries
        if not queries:
            logger.warning("gym %s has no queries — nothing to scrape", spec.gym_id)
            return ScrapeResult(0.0, 0, 0, 0)

        sem = asyncio.Semaphore(settings.worker_scrape_concurrency)
        per_query = await asyncio.gather(
            *(self._search_query(q, sem) for q in queries)
        )
        hits = [hit for q_hits in per_query for hit in q_hits]
        results_fetched = len(hits)
        fresh = build_outputs(hits)

        new_count, updated_count = await self._merge(fresh)
        apify_usd = round(
            results_fetched * settings.apify_cost_per_video_usd, 4
        )
        logger.info(
            "gym %s scrape: %d fetched, %d new / %d updated; Apify $%.4f",
            spec.gym_id,
            results_fetched,
            new_count,
            updated_count,
            apify_usd,
        )
        return ScrapeResult(
            apify_usd=apify_usd,
            results_fetched=results_fetched,
            new_count=new_count,
            updated_count=updated_count,
        )

    async def _search_query(
        self, query: str, sem: asyncio.Semaphore
    ) -> list:
        """One query's Apify run under the concurrency gate. A failure logs and
        drops just this query (the Apify spend on the rest is not wasted)."""
        async with sem:
            try:
                items = await self._apify.search(
                    query,
                    max_results=settings.worker_max_results_per_query,
                    language=SCRAPE_LANGUAGE,
                )
            except Exception as exc:  # noqa: BLE001 - one bad query never aborts
                logger.warning("query %r failed (dropped): %s", query, exc)
                return []
            return parse_search_items(items, query)

    async def _merge(self, fresh: list[VideoOutput]) -> tuple[int, int]:
        """Merge-upsert the deduped fresh videos; return (new, updated) counts."""
        rows = [self._to_row(v) for v in fresh]
        rows = [r for r in rows if r["video_id"]]
        if not rows:
            return 0, 0
        fresh_ids = [r["video_id"] for r in rows]
        existing = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_existing_video_ids.sql"),
            {"ids": fresh_ids},
        )
        existing_ids = {r["video_id"] for r in existing}
        new_count = sum(1 for vid in fresh_ids if vid not in existing_ids)
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_upsert_video.sql"), rows
        )
        return new_count, len(fresh_ids) - new_count

    @staticmethod
    def _to_row(video: VideoOutput) -> dict:
        """One ``VideoOutput`` → merge-upsert bind params."""
        return {
            "video_id": video_id_from_url(video.url),
            "url": video.url,
            "title": video.title,
            "description": video.description,
            "thumbnail_url": video.thumbnail_url,
            "channel_name": video.channel_name,
            "channel_url": video.channel_url,
            "channel_avatar_url": video.channel_avatar_url,
            "view_count": video.view_count,
            "like_count": video.like_count,
            "duration_seconds": video.duration_seconds,
            "source_queries": json.dumps(list(video.source_queries)),
            "relevance_index": video.relevance_index,
            "transcript_error": video.transcript_error,
            "transcript": video.transcript,
        }
