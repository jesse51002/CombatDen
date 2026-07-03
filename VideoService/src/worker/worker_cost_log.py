"""Stage 6 — append this run's per-stage spend to the ledger.

Writes one ``video_cost_log`` row per cost-bearing stage (search / enrich / embed
/ scan), each stamped with the gym + run id so per-run and per-gym spend are
queryable directly. Embed spend from BOTH the funnel probes and the enrich
summaries is folded into the single 'embed' row. Logs the run's total at the end.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from schema.cost_log import ExecutionType
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


@dataclass(frozen=True)
class RunCost:
    """The per-stage USD a run spent."""

    apify_usd: float = 0.0
    enrich_llm_usd: float = 0.0
    embed_usd: float = 0.0
    scan_llm_usd: float = 0.0

    @property
    def total_usd(self) -> float:
        return (
            self.apify_usd
            + self.enrich_llm_usd
            + self.embed_usd
            + self.scan_llm_usd
        )


class WorkerCostLog:
    """Appends a run's spend to ``video_cost_log``."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def log(self, gym_id: str, run_id: str, cost: RunCost) -> None:
        """Append the four per-stage rows and log the run total."""
        entries = [
            (ExecutionType.SEARCH, {"apify_usd": cost.apify_usd}, "scrape"),
            (ExecutionType.ENRICH, {"llm_usd": cost.enrich_llm_usd}, "enrich"),
            (
                ExecutionType.EMBED,
                {"llm_usd": cost.embed_usd},
                "query + summary embeddings",
            ),
            (ExecutionType.SCAN, {"llm_usd": cost.scan_llm_usd}, "scan"),
        ]
        now = datetime.now(timezone.utc)
        for execution_type, breakdown, note in entries:
            await self._insert(gym_id, run_id, execution_type, breakdown, note, now)
        logger.info(
            "gym %s run %s cost: search $%.4f enrich $%.4f embed $%.4f "
            "scan $%.4f = total $%.4f",
            gym_id,
            run_id,
            cost.apify_usd,
            cost.enrich_llm_usd,
            cost.embed_usd,
            cost.scan_llm_usd,
            cost.total_usd,
        )

    async def _insert(
        self,
        gym_id: str,
        run_id: str,
        execution_type: ExecutionType,
        breakdown: dict[str, float],
        note: str,
        at: datetime,
    ) -> None:
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_insert_cost.sql"),
            {
                "execution_type": execution_type.value,
                "gym_id": gym_id,
                "run_id": run_id,
                "at": at,
                "breakdown": json.dumps(breakdown),
                "note": note,
            },
        )
