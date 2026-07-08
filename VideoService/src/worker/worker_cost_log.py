"""Stage 6 — append this run's per-stage spend to the generic ledger.

Writes one ``cost_log`` row per cost-bearing stage (search / transcript / enrich
/ embed / scan), each stamped ``source='video'`` + the gym + run id so per-run
and per-gym spend are queryable directly. ``search`` is free (the YouTube Data
API within quota) and carries its quota usage as a breakdown diagnostic;
``transcript`` carries the Apify transcript spend. Embed spend from BOTH the
funnel probes and the enrich summaries is folded into the single 'embed' row.
Logs the run's total at the end.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

from schema.cost import CostSource, CostStage
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


@dataclass(frozen=True)
class RunCost:
    """The per-stage USD a run spent, plus the free search stage's quota usage."""

    search_usd: float = 0.0  # YouTube Data API — free within quota (always 0.0)
    youtube_quota_units: int = 0  # search-stage quota diagnostic (not billed)
    transcript_usd: float = 0.0  # Apify transcript fetches at enrich
    enrich_llm_usd: float = 0.0
    embed_usd: float = 0.0
    scan_llm_usd: float = 0.0

    @property
    def total_usd(self) -> float:
        return (
            self.search_usd
            + self.transcript_usd
            + self.enrich_llm_usd
            + self.embed_usd
            + self.scan_llm_usd
        )


class WorkerCostLog:
    """Appends a run's spend to ``cost_log``."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def log(self, gym_id: str, run_id: str, cost: RunCost) -> None:
        """Append the five per-stage rows and log the run total."""
        entries = [
            (
                CostStage.search,
                None,
                cost.search_usd,
                {"youtube_quota_units": cost.youtube_quota_units},
                "youtube data api",
            ),
            (
                CostStage.transcript,
                None,
                cost.transcript_usd,
                {"apify_usd": cost.transcript_usd},
                "apify transcripts",
            ),
            (
                CostStage.enrich,
                settings.enrich_model,
                cost.enrich_llm_usd,
                {"llm_usd": cost.enrich_llm_usd},
                "enrich",
            ),
            (
                CostStage.embed,
                settings.embedding_model,
                cost.embed_usd,
                {"llm_usd": cost.embed_usd},
                "query + summary embeddings",
            ),
            (
                CostStage.scan,
                settings.scan_model,
                cost.scan_llm_usd,
                {"llm_usd": cost.scan_llm_usd},
                "scan",
            ),
        ]
        for stage, model, cost_usd, breakdown, note in entries:
            await self._insert(gym_id, run_id, stage, model, cost_usd, breakdown, note)
        logger.info(
            "gym %s run %s cost: search $%.4f (%d quota) transcript $%.4f "
            "enrich $%.4f embed $%.4f scan $%.4f = total $%.4f",
            gym_id,
            run_id,
            cost.search_usd,
            cost.youtube_quota_units,
            cost.transcript_usd,
            cost.enrich_llm_usd,
            cost.embed_usd,
            cost.scan_llm_usd,
            cost.total_usd,
        )

    async def _insert(
        self,
        gym_id: str,
        run_id: str,
        stage: CostStage,
        model: str | None,
        cost_usd: float,
        breakdown: dict[str, float | int],
        note: str,
    ) -> None:
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_insert_cost.sql"),
            {
                "source": CostSource.video.value,
                "run_id": str(run_id),
                "gym_id": gym_id,
                "stage": stage.value,
                "model": model,
                "cost_usd": cost_usd,
                "breakdown": json.dumps(breakdown),
                "note": note,
            },
        )
