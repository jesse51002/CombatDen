"""The worker orchestrator: one ``run_tick`` = at most one gym's pipeline run.

A tick takes the global TTL-lease lock (returns quietly if another holder has
it), fails any run orphaned by a dead process, and — unless the system-wide
rolling run cap is already reached — DERIVES the single highest-priority gym that
is due (``worker_select_due_gym.sql``), opens a run, and drives the six stages
under a heartbeat that renews the lease. There is no queue: due-ness is computed
each tick from run / spec / curation timestamps, tier-sorted, under per-gym and
system rolling run caps. On success the run is completed; on any exception it is
failed with a truncated error — a failed run still advances the gym's last-run
watermark, so a deterministic failure does not hot-loop (it waits for a new
trigger or the weekly floor). The lock is always released.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import suppress
from pathlib import Path
from uuid import UUID, uuid4

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.services.resource_lock import ResourceLock
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings
from src.worker.worker_cost_log import RunCost, WorkerCostLog
from src.worker.worker_enricher import WorkerEnricher
from src.worker.worker_funnel import WorkerFunnel
from src.worker.worker_scanner import WorkerScanner
from src.worker.worker_scraper import WorkerScraper
from src.worker.worker_spec import WorkerSpec

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
LOCK_KEY = "video_worker_run"
ERROR_MAX_LEN = 1000


class WorkerAborted(Exception):
    """Raised between stages when the heartbeat lost the lock — the tick must
    stop (another process may already own the work)."""


class WorkerService:
    """Orchestrates one gym's scrape→enrich→scan run per tick."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        resource_lock: ResourceLock,
        spec: WorkerSpec,
        scraper: WorkerScraper,
        funnel: WorkerFunnel,
        enricher: WorkerEnricher,
        scanner: WorkerScanner,
        cost_log: WorkerCostLog,
    ) -> None:
        self._db = db_pool
        self._lock = resource_lock
        self._spec = spec
        self._scraper = scraper
        self._funnel = funnel
        self._enricher = enricher
        self._scanner = scanner
        self._cost_log = cost_log

    async def run_tick(self) -> None:
        """Process at most one due gym. No-op when the lock is held elsewhere,
        the system run cap is reached, or nothing is due."""
        token = uuid4()
        acquired = await self._lock.acquire_once(
            LOCK_KEY, token, ttl_seconds=settings.worker_lock_ttl_seconds
        )
        if not acquired:
            return
        try:
            await self._recover_orphans()
            if await self._system_cap_reached():
                logger.info("system run cap reached — skipping tick")
                return
            gym_id = await self._select_gym()
            if gym_id is None:
                return
            await self._process_gym(gym_id, token)
        finally:
            await self._lock.release(LOCK_KEY, token)

    async def _process_gym(self, gym_id: str, token: UUID) -> None:
        """Run the pipeline for one gym under a heartbeat, finalising the run."""
        abort = asyncio.Event()
        heartbeat = asyncio.create_task(self._heartbeat(token, abort))
        run_id: str | None = None
        try:
            run_id = await self._start_run(gym_id)
            await self._run_pipeline(gym_id, run_id, abort)
            await self._complete_run(run_id)
        except Exception as exc:  # noqa: BLE001 - failure is recorded, not raised
            logger.error("run failed for gym %s", gym_id, exc_info=True)
            if run_id is not None:
                await self._fail_run(run_id, str(exc)[:ERROR_MAX_LEN])
        finally:
            heartbeat.cancel()
            with suppress(asyncio.CancelledError):
                await heartbeat

    async def _run_pipeline(
        self, gym_id: str, run_id: str, abort: asyncio.Event
    ) -> None:
        """The six stages in order, checking the abort flag between each."""
        self._check_abort(abort)
        spec = await self._spec.load(gym_id)
        self._check_abort(abort)
        scrape = await self._scraper.scrape(spec)
        self._check_abort(abort)
        funnel = await self._funnel.select(spec)
        self._check_abort(abort)
        enrich = await self._enricher.enrich(gym_id, funnel.candidate_ids)
        self._check_abort(abort)
        scan = await self._scanner.scan(spec, run_id, funnel.candidate_ids)
        self._check_abort(abort)
        cost = RunCost(
            apify_usd=scrape.apify_usd,
            enrich_llm_usd=enrich.llm_usd,
            embed_usd=funnel.embed_usd + enrich.embed_usd,
            scan_llm_usd=scan.llm_usd,
        )
        await self._cost_log.log(gym_id, run_id, cost)

    @staticmethod
    def _check_abort(abort: asyncio.Event) -> None:
        if abort.is_set():
            raise WorkerAborted("heartbeat lost the worker lock")

    async def _heartbeat(self, token: UUID, abort: asyncio.Event) -> None:
        """Renew the lease every interval; on a lost lease set the abort flag."""
        while True:
            await asyncio.sleep(settings.worker_heartbeat_seconds)
            renewed = await self._lock.renew(
                LOCK_KEY, token, ttl_seconds=settings.worker_lock_ttl_seconds
            )
            if not renewed:
                logger.error("heartbeat lost the lock — aborting run")
                abort.set()
                return

    async def _recover_orphans(self) -> None:
        """Fail every 'running' run — dead, since we hold the exclusive lock. No
        re-enqueue: the derivation re-selects the gym when it is next due (subject
        to the run caps); this just clears the stuck 'running' row so the state
        stays truthful and the run-cap counts stay accurate."""
        async with self._db.session() as session:
            result = await session.execute(
                text(load_sql(SQL_DIR / "worker_fail_orphans.sql"))
            )
            orphans = result.mappings().all()
            await session.commit()
        if orphans:
            logger.warning("recovered %d orphaned run(s)", len(orphans))

    async def _system_cap_reached(self) -> bool:
        """True when runs started across all gyms in the rolling window already
        reach the system-wide cap (the global Apify/quota budget guard)."""
        row = await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_system_run_count.sql"),
            {"cap_window_hours": settings.worker_cap_window_hours},
        )
        count = int(row["runs_in_window"]) if row else 0
        return count >= settings.worker_system_run_cap

    async def _select_gym(self) -> str | None:
        """Derive the highest-priority DUE gym under its per-gym run cap, or None
        when nothing is due (see worker_select_due_gym.sql)."""
        row = await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_select_due_gym.sql"),
            {
                "cap_window_hours": settings.worker_cap_window_hours,
                "gym_run_cap": settings.worker_gym_run_cap,
                "curation_batch_hours": settings.worker_curation_batch_hours,
                "weekly_days": settings.worker_weekly_refresh_days,
            },
        )
        return str(row["gym_id"]) if row else None

    async def _start_run(self, gym_id: str) -> str:
        row = await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_insert_run.sql"), {"gym_id": gym_id}
        )
        if row is None:
            raise RuntimeError(f"failed to open a run for gym {gym_id}")
        return str(row["run_id"])

    async def _complete_run(self, run_id: str) -> None:
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_complete_run.sql"), {"run_id": run_id}
        )

    async def _fail_run(self, run_id: str, error: str) -> None:
        await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_fail_run.sql"),
            {"run_id": run_id, "error": error},
        )
