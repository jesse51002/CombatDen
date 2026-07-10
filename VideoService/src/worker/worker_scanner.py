"""Scan sweep — a gym-agnostic keep/drop pass that settles + re-judges feed rows.

The target set (``worker_scan_targets.sql``) is enriched feed rows (a ``video_rag``
row) under the strike ceiling, grouped by gym, matching EITHER arm: (A) a ``pending``
row in the gym's LATEST NON-FAILED run (its first-ever verdict), OR (B) an
``automatic`` row in the gym's LATEST COMPLETED (SERVED) run whose ``scanned_at``
predates a gym ``feed_update`` spec version that has settled ≥
``worker_feed_update_rescan_delay_hours`` — the feed-learning RE-SCAN. Arm B targets
the SERVED run, not the latest non-failed one, so an in-flight ``running`` run never
diverts the re-judge from what members actually see. The sweep DRAINS it: per gym, it
loads that gym's LATEST spec at scan time (judge against the current criteria — the
``feed_update`` folded in the owner's manual signals), batches the candidates, and
runs a TEXT-ONLY keep/drop against each candidate's summary + structured enrich
outputs (genre, disciplines, facets). The enrich step already did the multimodal
(thumbnail) pass ONCE and folded the visual detail into the summary, so scan never
re-fetches the thumbnail — cheaper, and it matters because scan runs per-gym (a video
in many feeds is scanned many times) while enrich runs once per video.

Verdicts are written by UPDATE (``worker_update_verdict.sql``): an automatic row is
flipped to accepted/rejected (arm B flips accepted<->rejected only when the judgment
changes) and stamped ``scanned_at = now()``, guarded by ``curation_type <> 'manual'``
so an owner's explicit keep/reject verdict is never overwritten and the row is never
flipped to ``pending`` (which would blank it from the served feed). Because arm A and
arm B can select rows from DIFFERENT runs for the same gym (arm A the fresh running
run, arm B the served completed one), each verdict is keyed by ITS OWN row's
``video_run_id`` — never a single per-gym run — so a verdict always lands on the row
it judged. A verdicted video gets its strike counter reset.

Strike semantics — there is NO default-to-rejected: a batch whose LLM call raises
bumps ``failure_count`` for EVERY video in the batch and leaves the rows ``pending``
(retried next sweep); a video the model omits from an otherwise-successful batch is
bumped alone and stays ``pending``. Spend is one ``scan`` cost row per gym per sweep.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from string import Template

from src.shared.database import DirectDatabasePool
from src.shared.interfaces.llm_client import LLMClient
from src.shared.sql_loader import load_sql
from src.shared.util.jsonb import as_list
from src.worker.schema.scan_batch import ScanBatchResult
from src.worker.worker_abort import check_abort
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog
from src.worker.worker_util import chunks

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
SCAN_PROMPT_PATH = Path(__file__).resolve().parent / "prompts" / "worker_scan.md"

SCAN_STATUS_ACCEPTED = "accepted"
SCAN_STATUS_REJECTED = "rejected"


class WorkerScanner:
    """Drains the scan target set (first-scan ``pending`` rows + feed_update
    re-scan rows): per gym, a text-only keep/drop against the gym's latest spec,
    verdicts written by UPDATE (auto rows only), hard failures struck."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        llm_client: LLMClient,
        cost_log: WorkerCostLog,
    ) -> None:
        self._db = db_pool
        self._llm = llm_client
        self._cost_log = cost_log

    async def drain(self, abort: asyncio.Event) -> bool:
        """Scan every pending target, grouped by gym. True iff there was work."""
        targets = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_scan_targets.sql"),
            {
                "max_failures": settings.worker_failure_max,
                "rescan_delay_hours": (
                    settings.worker_feed_update_rescan_delay_hours
                ),
            },
        )
        if not targets:
            return False
        by_gym: dict[str, list[dict]] = defaultdict(list)
        for row in targets:
            by_gym[str(row["gym_id"])].append(row)
        for gym_id, rows in by_gym.items():
            check_abort(abort)
            await self._scan_gym(gym_id, rows, abort)
        return True

    async def _scan_gym(
        self, gym_id: str, rows: list[dict], abort: asyncio.Event
    ) -> None:
        """Scan one gym's candidates against its latest spec. The accumulated LLM
        spend is logged in a ``finally`` so an abort between batches still records
        what was already spent (one ``scan`` row per gym per sweep)."""
        criteria = await self._load_criteria(gym_id)
        if criteria is None:
            logger.warning("gym %s has no spec at scan time — skipped", gym_id)
            return
        # An attribution pointer for the single per-gym cost row (rows may span two
        # runs — arm A's running run and arm B's completed run — but the cost row is
        # per-gym-per-sweep, so any of the gym's runs is a fine pointer).
        cost_run_id = str(rows[0]["video_run_id"])
        total_cost = 0.0
        scanned = 0
        try:
            for batch in chunks(rows, settings.scan_batch_size):
                check_abort(abort)
                total_cost += await self._scan_batch(criteria, gym_id, batch)
                scanned += len(batch)
        finally:
            if scanned:
                await self._cost_log.log_scan(
                    gym_id, cost_run_id, scan_usd=total_cost, scanned=scanned
                )
        logger.info(
            "gym %s scan: %d judged; LLM $%.4f", gym_id, scanned, total_cost
        )

    async def _scan_batch(
        self, criteria: tuple[str, str], gym_id: str, batch: list[dict]
    ) -> float:
        """One batch's text-only keep/drop. On an LLM exception the whole batch is
        struck and left pending; a per-id miss is struck alone and left pending.
        Each verdict is keyed by its OWN row's ``video_run_id`` (arm A and arm B may
        select rows from different runs for the same gym)."""
        prompt = self._build_batch(criteria, batch)
        try:
            result, cost = await self._llm.complete_structured_with_cost(
                [{"role": "user", "content": prompt}],
                schema=ScanBatchResult,
                model=settings.scan_model,
            )
        except Exception as exc:  # noqa: BLE001 - a bad batch strikes, not aborts
            logger.warning("scan batch failed (strike, stays pending): %s", exc)
            await self._bump_failure([r["video_id"] for r in batch])
            return 0.0

        run_by_id = {r["video_id"]: str(r["video_run_id"]) for r in batch}
        verdicts = {
            v.video_id: v.is_good
            for v in result.verdicts
            if v.video_id in run_by_id
        }
        dropped = len(result.verdicts) - len(verdicts)
        if dropped:
            logger.warning(
                "scan batch returned %d id(s) not in the batch (dropped)", dropped
            )
        await self._write_verdicts(gym_id, run_by_id, verdicts)
        await self._reset_failure(list(verdicts))
        missing = [vid for vid in run_by_id if vid not in verdicts]
        if missing:
            logger.warning(
                "no verdict for %d id(s) — struck, left pending", len(missing)
            )
            await self._bump_failure(missing)
        return cost

    async def _write_verdicts(
        self, gym_id: str, run_by_id: dict[str, str], verdicts: dict[str, bool]
    ) -> None:
        """Flip each verdicted auto row to accepted/rejected by UPDATE, each keyed
        by its own row's ``video_run_id``."""
        params = self._verdict_params(gym_id, run_by_id, verdicts)
        if not params:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_update_verdict.sql"), params
        )

    async def _reset_failure(self, video_ids: list[str]) -> None:
        """Clear the strike counter on videos that got a verdict."""
        if not video_ids:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_reset_failure.sql"),
            [{"video_id": vid} for vid in video_ids],
        )

    async def _bump_failure(self, video_ids: list[str]) -> None:
        """Bump the strike counter on videos a batch failed / omitted."""
        if not video_ids:
            return
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_bump_failure.sql"),
            [{"video_id": vid} for vid in video_ids],
        )

    async def _load_criteria(self, gym_id: str) -> tuple[str, str] | None:
        """The gym's latest (videos_desc, avoid_desc), or None when it has no
        spec. Read at scan time so verdicts judge against the CURRENT criteria."""
        row = await self._db.fetch_one(
            load_sql(SQL_DIR / "worker_spec_load_latest.sql"), {"gym_id": gym_id}
        )
        if row is None:
            return None
        return row["videos_desc"] or "", row["avoid_desc"] or ""

    @staticmethod
    def _verdict_params(
        gym_id: str, run_by_id: dict[str, str], verdicts: dict[str, bool]
    ) -> list[dict]:
        """Bind rows for the verdict UPDATE; each keyed by its own row's
        ``video_run_id``; rejected rows stamp rejected_at."""
        now = datetime.now(timezone.utc)
        return [
            {
                "gym_id": gym_id,
                "video_id": video_id,
                "video_run_id": run_by_id[video_id],
                "verdict": (
                    SCAN_STATUS_ACCEPTED if is_good else SCAN_STATUS_REJECTED
                ),
                "rejected_at": None if is_good else now,
            }
            for video_id, is_good in verdicts.items()
        ]

    @staticmethod
    def _build_batch(criteria: tuple[str, str], batch: list[dict]) -> str:
        """The text-only scan prompt for one batch. Each candidate is listed with
        its structured enrich outputs (genre, disciplines, facets) and its detailed
        summary — the summary already folds in the thumbnail's visual detail, so no
        image is attached."""
        lines: list[str] = []
        for index, row in enumerate(batch, start=1):
            genre = row["genre"] or "unknown"
            disciplines = ", ".join(as_list(row["disciplines"])) or "unknown"
            lines.append(
                f"- candidate {index}\n"
                f"  video_id: {row['video_id']}\n"
                f"  title: {row['title']}\n"
                f"  channel: {row['channel_name']}\n"
                f"  genre: {genre}\n"
                f"  disciplines: {disciplines}\n"
                f"  facets: {WorkerScanner._facets_text(row['facets'])}\n"
                f"  summary: {row['summary']}"
            )
        return Template(
            SCAN_PROMPT_PATH.read_text(encoding="utf-8")
        ).safe_substitute(
            videos_desc=criteria[0],
            avoid_desc=criteria[1],
            videos_block="\n".join(lines),
        )

    @staticmethod
    def _facets_text(facets: object) -> str:
        """Render the enrich ``facets`` map compactly for the prompt, tolerating
        the driver returning either a decoded dict or a JSON string."""
        if isinstance(facets, str):
            return facets or "{}"
        if facets:
            return json.dumps(facets, separators=(",", ":"))
        return "{}"
