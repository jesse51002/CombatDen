"""Scrape step — scrape the spec's queries into the shared pool, then write the
run's PENDING feed rows.

Discovery + metadata come from the official YouTube Data API (two calls per
query: ``search.list`` for the ids, ``videos.list`` for stats + duration),
concurrent under a semaphore; a failed query is logged and dropped, never
aborting the run (partial scrape is fine). Results are transformed by the pure
``worker_transforms`` and merge-upserted into ``video``: new videos land untagged
and transcript-less (the enrich sweep fetches transcripts lazily), existing
videos keep their content (never wiped with NULLs) and gain the surfacing query.
The YouTube Data API is free within quota, so the scrape reports its quota usage
(a diagnostic) and a spend of $0.

After the merge comes the AVATAR pass (``worker_avatars``): one ``channels.list``
call per ≤50 of the scrape's distinct creators fills the ones with no avatar and
refreshes the rest (YouTube avatar URLs rotate when a creator changes their
picture). Its calls are counted into the same ``youtube_quota_units`` the run
reports and logs — the avatar pass is never uncounted quota.

``write_feed`` is the scrape step's ONLY feed write: it carries the previous
completed run's rows forward FIRST (ALL rows incremental, manual-only fresh), then
inserts every funnel candidate as a ``pending`` row ``ON CONFLICT DO NOTHING`` so a
carried row always wins. The run is left ``running`` — the enrich + scan sweeps and
the finalizer take it from there; nothing is enriched, scanned, or completed here.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import text

from schema.video_output import VideoOutput
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.util.video_id import video_id_from_url
from src.worker.worker_avatars import WorkerAvatarResolver
from src.worker.worker_config import settings
from src.worker.worker_spec import SpecData
from src.worker.worker_transforms import (
    build_outputs,
    parse_youtube_items,
    youtube_item_id,
)
from src.worker.worker_youtube import WorkerYouTubeClient

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
SCRAPE_LANGUAGE = "en"
# search.list costs 100 quota units per query; videos.list adds ~1/query (a
# rounding error), so the search cost dominates the per-run quota diagnostic.
QUOTA_UNITS_PER_SEARCH = 100
# Fresh-run carry-forward: copy ONLY the owner's manual verdicts (incremental
# copies ALL prior rows — the empty clause).
MANUAL_ONLY_CLAUSE = "AND curation_type = 'manual'"


@dataclass(frozen=True)
class ScrapeResult:
    """What one scrape did: spend + quota + how much of the pool it touched."""

    search_usd: float  # YouTube Data API is free within quota → always 0.0
    # The run's TOTAL quota diagnostic: ~100 units per spec query plus 1 per
    # channels.list avatar batch.
    youtube_quota_units: int
    results_fetched: int  # raw video items returned across all queries
    new_count: int
    updated_count: int
    avatar_quota_units: int  # the avatar pass's share of the units above
    channels_resolved: int  # creators whose avatar this run filled/refreshed


class WorkerScraper:
    """Runs the spec's queries through the YouTube Data API and merges results
    into the pool."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        youtube_client: WorkerYouTubeClient,
        avatars: WorkerAvatarResolver,
    ) -> None:
        self._db = db_pool
        self._youtube = youtube_client
        self._avatars = avatars

    async def scrape(self, spec: SpecData) -> ScrapeResult:
        """Fetch every spec query, merge-upsert the results into ``video``, then
        fill/refresh the creator avatars of the channels that scrape surfaced."""
        queries = spec.queries
        if not queries:
            logger.warning("gym %s has no queries — nothing to scrape", spec.gym_id)
            return ScrapeResult(
                search_usd=0.0,
                youtube_quota_units=0,
                results_fetched=0,
                new_count=0,
                updated_count=0,
                avatar_quota_units=0,
                channels_resolved=0,
            )

        sem = asyncio.Semaphore(settings.worker_scrape_concurrency)
        per_query = await asyncio.gather(
            *(self._search_query(q, sem) for q in queries)
        )
        hits = [hit for q_hits in per_query for hit in q_hits]
        results_fetched = len(hits)
        fresh = build_outputs(hits)

        new_count, updated_count = await self._merge(fresh)
        # AFTER the merge: the avatar write fans out by channel_url, so the rows
        # this scrape just inserted must already exist to be covered by it.
        avatars = await self._avatars.refresh_for_scrape(fresh)
        quota_units = (
            len(queries) * QUOTA_UNITS_PER_SEARCH + avatars.quota_units
        )
        logger.info(
            "gym %s scrape: %d fetched, %d new / %d updated, %d avatars; "
            "YouTube ~%d quota units (free)",
            spec.gym_id,
            results_fetched,
            new_count,
            updated_count,
            avatars.channels_resolved,
            quota_units,
        )
        return ScrapeResult(
            search_usd=0.0,
            youtube_quota_units=quota_units,
            results_fetched=results_fetched,
            new_count=new_count,
            updated_count=updated_count,
            avatar_quota_units=avatars.quota_units,
            channels_resolved=avatars.channels_resolved,
        )

    async def _search_query(self, query: str, sem: asyncio.Semaphore) -> list:
        """One query's YouTube fetch (search + details) under the concurrency
        gate. A failure logs and drops just this query (the rest are unaffected;
        the free quota already spent on them is not wasted)."""
        async with sem:
            try:
                search_items = await self._youtube.search(
                    query,
                    max_results=settings.worker_max_results_per_query,
                    language=SCRAPE_LANGUAGE,
                )
                ids = [
                    vid
                    for vid in (youtube_item_id(i) for i in search_items)
                    if vid
                ]
                details = await self._youtube.list_videos(ids) if ids else []
            except Exception as exc:  # noqa: BLE001 - one bad query never aborts
                logger.warning("query %r failed (dropped): %s", query, exc)
                return []
            details_by_id = {youtube_item_id(d): d for d in details}
            return parse_youtube_items(search_items, details_by_id, query)

    async def write_feed(
        self, spec: SpecData, run_id: str, candidate_ids: list[str]
    ) -> int:
        """Write this run's feed rows in ONE txn: carry the previous completed
        run's rows forward FIRST, then insert every candidate as ``pending``.

        Carried rows win the ``ON CONFLICT`` (inserted first), so a carried
        manual/verdict row is never downgraded to pending. Returns the number of
        candidates offered to the pending insert (pre-conflict)."""
        async with self._db.session() as session:
            if spec.prev_run_id is not None:
                clause = MANUAL_ONLY_CLAUSE if spec.criteria_changed else ""
                cf_sql = load_sql(
                    SQL_DIR / "worker_carry_forward.sql", {"manual_only": clause}
                )
                await session.execute(
                    text(cf_sql),
                    {"new_run_id": run_id, "prev_run_id": spec.prev_run_id},
                )
            params = [
                {"gym_id": spec.gym_id, "video_id": vid, "run_id": run_id}
                for vid in candidate_ids
            ]
            if params:
                await session.execute(
                    text(load_sql(SQL_DIR / "worker_insert_pending.sql")), params
                )
            await session.commit()
        logger.info(
            "gym %s scrape feed: %d candidates written as pending (run %s)",
            spec.gym_id,
            len(candidate_ids),
            run_id,
        )
        return len(candidate_ids)

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
