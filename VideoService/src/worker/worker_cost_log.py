"""Append per-step spend to the generic ``cost_log`` ledger.

One row per cost-bearing stage (search / transcript / enrich / embed / scan),
each stamped ``source='video'`` + ``stage`` + ``model`` (NULL for the free search
stage and the Apify transcript stage) + ``cost_usd`` (the row's single USD total;
``breakdown`` carries the component detail). Attribution differs by STEP, because
the worker's steps are decoupled:

  * SCRAPE (per gym / per run) — ``search`` (free; quota units diagnostic) +
    ``embed`` (the tier-2 funnel probe embeds), both stamped that gym + run.
  * ENRICH (a gym-agnostic sweep) — ``transcript`` + ``enrich`` + ``embed``, all
    stamped ``gym_id = NULL`` and ``run_id = NULL``: a swept video is shared across
    gyms, so per-gym attribution would be arbitrary.
  * SCAN (per gym / per sweep) — one ``scan`` row stamped that gym + its latest run.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from schema.cost import CostSource, CostStage
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


class WorkerCostLog:
    """Appends a step's spend rows to ``cost_log``."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def log_scrape(
        self,
        gym_id: str,
        run_id: str,
        *,
        youtube_quota_units: int,
        embed_usd: float,
        avatar_quota_units: int = 0,
        channels_resolved: int = 0,
    ) -> None:
        """The scrape step's rows: the free ``search`` (quota diagnostic) and the
        tier-2 probe ``embed``, both attributed to this gym + run.

        ``youtube_quota_units`` is the run's TOTAL — search plus the avatar pass's
        ``channels.list`` calls — and the avatar share is broken out beside it so
        the ledger shows what the avatars cost without a second row (they are the
        same free API and the same run). The avatar args default to 0 because the
        failure path logs this row before the scrape has produced a result."""
        await self._insert(
            gym_id,
            run_id,
            CostStage.search,
            None,
            0.0,
            {
                "youtube_quota_units": youtube_quota_units,
                "avatar_quota_units": avatar_quota_units,
                "channels_resolved": channels_resolved,
            },
            "youtube data api",
        )
        await self._insert(
            gym_id,
            run_id,
            CostStage.embed,
            settings.embedding_model,
            embed_usd,
            {"llm_usd": embed_usd},
            "tier-2 query embeddings",
        )
        logger.info(
            "gym %s run %s scrape cost: search $0 (%d quota, %d of it avatars) "
            "embed $%.4f",
            gym_id,
            run_id,
            youtube_quota_units,
            avatar_quota_units,
            embed_usd,
        )

    async def log_enrich(
        self,
        *,
        transcript_usd: float,
        enrich_usd: float,
        embed_usd: float,
        videos: int,
        transcripts_fetched: int,
        actor_starts: int,
    ) -> None:
        """The enrich sweep's POOL-LEVEL rows (gym_id / run_id NULL): the Apify
        ``transcript`` spend (batched — priced per transcript scraped + per actor
        start), the multimodal ``enrich`` spend, and the summary ``embed`` spend."""
        breakdown = {
            "videos": videos,
            "transcripts_fetched": transcripts_fetched,
            "actor_starts": actor_starts,
        }
        await self._insert(
            None,
            None,
            CostStage.transcript,
            None,
            transcript_usd,
            breakdown,
            "apify transcripts (sweep)",
        )
        await self._insert(
            None,
            None,
            CostStage.enrich,
            settings.enrich_model,
            enrich_usd,
            breakdown,
            "enrich (sweep)",
        )
        await self._insert(
            None,
            None,
            CostStage.embed,
            settings.embedding_model,
            embed_usd,
            breakdown,
            "summary embeddings (sweep)",
        )
        logger.info(
            "enrich sweep cost: transcript $%.4f enrich $%.4f embed $%.4f "
            "(%d videos, %d transcripts fetched, %d actor runs)",
            transcript_usd,
            enrich_usd,
            embed_usd,
            videos,
            transcripts_fetched,
            actor_starts,
        )

    async def log_scan(
        self, gym_id: str, run_id: str, *, scan_usd: float, scanned: int
    ) -> None:
        """The scan sweep's per-gym row: the batched keep/drop ``scan`` spend,
        attributed to this gym + its latest run."""
        await self._insert(
            gym_id,
            run_id,
            CostStage.scan,
            settings.scan_model,
            scan_usd,
            {"llm_usd": scan_usd, "scanned": scanned},
            "scan (sweep)",
        )
        logger.info(
            "gym %s run %s scan cost: $%.4f (%d scanned)",
            gym_id,
            run_id,
            scan_usd,
            scanned,
        )

    async def _insert(
        self,
        gym_id: str | None,
        run_id: str | None,
        stage: CostStage,
        model: str | None,
        cost_usd: float,
        breakdown: dict[str, float | int],
        note: str,
    ) -> None:
        """Append one ``cost_log`` row. ``gym_id`` / ``run_id`` may be NULL (a
        pool-level sweep row) — they are never coerced to the string 'None'."""
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_insert_cost.sql"),
            {
                "source": CostSource.video.value,
                "run_id": str(run_id) if run_id is not None else None,
                "gym_id": gym_id,
                "stage": stage.value,
                "model": model,
                "cost_usd": cost_usd,
                "breakdown": json.dumps(breakdown),
                "note": note,
            },
        )
