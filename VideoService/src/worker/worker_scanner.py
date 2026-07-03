"""Stage 5 — batched keep/drop scan + the carry-forward feed write.

Candidates that have a ``video_rag`` row (enriched) are scanned in batches: one
structured LLM call judges ``is_good`` per video against the gym's criteria.
Hallucinated ids are dropped; a batch id that gets no verdict is retried once,
then defaulted to rejected. The verdicts are written in ONE transaction that
first CARRIES FORWARD the previous completed run's rows (all rows in incremental
mode, only the owner's manual verdicts in fresh mode) so carried rows always win
the ``ON CONFLICT`` over a fresh automatic verdict.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from string import Template

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.interfaces.llm_client import LLMClient
from src.shared.sql_loader import load_sql
from src.worker.schema.scan_batch import ScanBatchResult
from src.worker.worker_config import settings
from src.worker.worker_spec import SpecData

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
SCAN_PROMPT_PATH = Path(__file__).resolve().parent / "prompts" / "worker_scan.md"

MANUAL_ONLY_CLAUSE = "AND curation_type = 'manual'"
SCAN_STATUS_ACCEPTED = "accepted"
SCAN_STATUS_REJECTED = "rejected"


@dataclass(frozen=True)
class ScanResult:
    """What the scan did: spend + the accepted/rejected split."""

    llm_usd: float = 0.0
    accepted_count: int = 0
    rejected_count: int = 0
    scanned_count: int = 0


class WorkerScanner:
    """Scans the enriched candidates and writes the run's feed."""

    def __init__(self, db_pool: DirectDatabasePool, llm_client: LLMClient) -> None:
        self._db = db_pool
        self._llm = llm_client

    async def scan(
        self, spec: SpecData, run_id: str, candidate_ids: list[str]
    ) -> ScanResult:
        """Scan the enriched candidates and write this run's feed rows."""
        rows = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_load_scan_candidates.sql"),
            {"ids": candidate_ids},
        )
        verdicts, llm_usd = await self._scan_with_retry(spec, rows)
        accepted = sum(1 for good in verdicts.values() if good)
        rejected = len(verdicts) - accepted
        await self._write_feed(spec, run_id, verdicts)
        logger.info(
            "gym %s scan: %d scanned → %d accepted / %d rejected; LLM $%.4f",
            spec.gym_id,
            len(rows),
            accepted,
            rejected,
            llm_usd,
        )
        return ScanResult(
            llm_usd=llm_usd,
            accepted_count=accepted,
            rejected_count=rejected,
            scanned_count=len(rows),
        )

    async def _scan_with_retry(
        self, spec: SpecData, rows: list[dict]
    ) -> tuple[dict[str, bool], float]:
        """Verdict per candidate id, retrying the ones a batch missed once, then
        defaulting any still-missing to rejected."""
        if not rows:
            return {}, 0.0
        verdicts, cost = await self._scan_pass(spec, rows)
        missing = [r for r in rows if r["video_id"] not in verdicts]
        if missing:
            retry_verdicts, retry_cost = await self._scan_pass(spec, missing)
            verdicts.update(retry_verdicts)
            cost += retry_cost
        for row in rows:
            if row["video_id"] not in verdicts:
                logger.warning(
                    "no verdict for %s after retry — defaulting to rejected",
                    row["video_id"],
                )
                verdicts[row["video_id"]] = False
        return verdicts, cost

    async def _scan_pass(
        self, spec: SpecData, rows: list[dict]
    ) -> tuple[dict[str, bool], float]:
        """One scan pass over ``rows`` in batches; merged verdicts + total cost."""
        sem = asyncio.Semaphore(settings.worker_scan_concurrency)
        batches = list(self._chunks(rows, settings.scan_batch_size))
        results = await asyncio.gather(
            *(self._scan_batch(spec, batch, sem) for batch in batches)
        )
        verdicts: dict[str, bool] = {}
        cost = 0.0
        for batch_verdicts, batch_cost in results:
            verdicts.update(batch_verdicts)
            cost += batch_cost
        return verdicts, cost

    async def _scan_batch(
        self, spec: SpecData, batch: list[dict], sem: asyncio.Semaphore
    ) -> tuple[dict[str, bool], float]:
        """One batch's scan call. Drops ids not in the batch; a failure → {}."""
        async with sem:
            prompt = self._build_prompt(spec, batch)
            try:
                result, cost = await self._llm.complete_structured_with_cost(
                    [{"role": "user", "content": prompt}],
                    schema=ScanBatchResult,
                    model=settings.scan_model,
                )
            except Exception as exc:  # noqa: BLE001 - a bad batch retries, not aborts
                logger.warning("scan batch failed (will retry ids): %s", exc)
                return {}, 0.0
            batch_ids = {r["video_id"] for r in batch}
            verdicts = {
                v.video_id: v.is_good
                for v in result.verdicts
                if v.video_id in batch_ids
            }
            dropped = len(result.verdicts) - len(verdicts)
            if dropped:
                logger.warning(
                    "scan batch returned %d id(s) not in the batch (dropped)",
                    dropped,
                )
            return verdicts, cost

    async def _write_feed(
        self, spec: SpecData, run_id: str, verdicts: dict[str, bool]
    ) -> None:
        """Carry forward prior rows, then insert this run's verdicts — one txn."""
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
            params = self._verdict_params(spec.gym_id, run_id, verdicts)
            if params:
                await session.execute(
                    text(load_sql(SQL_DIR / "worker_insert_verdict.sql")), params
                )
            await session.commit()

    @staticmethod
    def _verdict_params(
        gym_id: str, run_id: str, verdicts: dict[str, bool]
    ) -> list[dict]:
        """Bind rows for the verdict insert; rejected rows stamp rejected_at."""
        now = datetime.now(timezone.utc)
        return [
            {
                "gym_id": gym_id,
                "video_id": video_id,
                "run_id": run_id,
                "scan_status": (
                    SCAN_STATUS_ACCEPTED if is_good else SCAN_STATUS_REJECTED
                ),
                "rejected_at": None if is_good else now,
            }
            for video_id, is_good in verdicts.items()
        ]

    @staticmethod
    def _build_prompt(spec: SpecData, batch: list[dict]) -> str:
        """The scan prompt for one batch (criteria + a per-video block)."""
        lines: list[str] = []
        for row in batch:
            genre = row["genre"] or "unknown"
            lines.append(
                f"- video_id: {row['video_id']}\n"
                f"  title: {row['title']}\n"
                f"  channel: {row['channel_name']}\n"
                f"  genre: {genre}\n"
                f"  summary: {row['summary']}"
            )
        return Template(
            SCAN_PROMPT_PATH.read_text(encoding="utf-8")
        ).safe_substitute(
            videos_desc=spec.videos_desc,
            avoid_desc=spec.avoid_desc,
            videos_block="\n".join(lines),
        )

    @staticmethod
    def _chunks(seq: Sequence[dict], size: int) -> Iterator[list[dict]]:
        """Yield ``seq`` in lists of at most ``size``."""
        for start in range(0, len(seq), size):
            yield list(seq[start : start + size])
