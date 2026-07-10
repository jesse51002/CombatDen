"""The worker orchestrator: one ``run_tick`` runs three DB-backed steps under one
lock hold.

There is no per-gym end-to-end pipeline anymore. A tick takes the global TTL-lease
lock (returns quietly if another holder has it), starts a heartbeat that renews the
lease, and then, IN ORDER:

  1. CLEANUP (always, cheap) — delete videos at the strike ceiling, so the finalize
     step's terminal-fraction denominators reflect the shrunk feed.
  2. FINALIZE (always, cheap) — complete / fail every 'running' run from its feed
     rows (90%-terminal completes; 0-row-after-grace and TTL-exceeded fail).
  3. ONE HEAVY STEP, first-with-work, drained fully — check SCAN, then ENRICH, then
     SCRAPE (backlog first; scrape is the quota-bound ingest, so it goes last). The
     first step that has work is drained completely this tick, then the tick ends.

Runs are now a legitimate long-lived multi-tick state ('running' full of 'pending'
feed rows), so there is NO orphan rule — crash recovery is free (every step is
DB-derived + idempotent; the finalize 0-row/TTL guards catch any pathologically
stuck run). Only the SCRAPE step opens runs, so the per-gym + system rolling run
caps still bound exactly the quota-limited work. The lock is always released.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import suppress
from pathlib import Path
from uuid import UUID, uuid4

from src.shared.database import DirectDatabasePool
from src.shared.services.resource_lock import ResourceLock
from src.shared.sql_loader import load_sql
from src.worker.worker_abort import WorkerAborted, check_abort
from src.worker.worker_cleanup import WorkerCleanup
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog
from src.worker.worker_enricher import WorkerEnricher
from src.worker.worker_finalizer import WorkerFinalizer
from src.worker.worker_funnel import WorkerFunnel
from src.worker.worker_scanner import WorkerScanner
from src.worker.worker_scraper import WorkerScraper
from src.worker.worker_spec import WorkerSpec

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"
LOCK_KEY = "video_worker_run"

__all__ = ["WorkerAborted", "WorkerService"]


class WorkerService:
    """Orchestrates the cleanup → finalize → one-heavy-step tick."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        resource_lock: ResourceLock,
        spec: WorkerSpec,
        scraper: WorkerScraper,
        funnel: WorkerFunnel,
        enricher: WorkerEnricher,
        scanner: WorkerScanner,
        cleanup: WorkerCleanup,
        finalizer: WorkerFinalizer,
        cost_log: WorkerCostLog,
    ) -> None:
        self._db = db_pool
        self._lock = resource_lock
        self._spec = spec
        self._scraper = scraper
        self._funnel = funnel
        self._enricher = enricher
        self._scanner = scanner
        self._cleanup = cleanup
        self._finalizer = finalizer
        self._cost_log = cost_log

    async def run_tick(self, stop: asyncio.Event | None = None) -> None:
        """Cleanup → finalize → the first heavy step with work, drained fully.
        No-op when the lock is held elsewhere.

        ``stop`` is the process-wide SIGINT/SIGTERM event: while a tick is in
        flight it is mirrored onto the tick's abort flag so a long drain stops at
        the next ``check_abort`` (between chunks / videos / gyms), not only between
        ticks — otherwise a mid-drain worker is unkillable. The abort is also set
        by the heartbeat on a lost lease; both share one flag."""
        token = uuid4()
        acquired = await self._lock.acquire_once(
            LOCK_KEY, token, ttl_seconds=settings.worker_lock_ttl_seconds
        )
        if not acquired:
            return
        abort = asyncio.Event()
        heartbeat = asyncio.create_task(self._heartbeat(token, abort))
        stop_watch = (
            asyncio.create_task(self._mirror_stop(stop, abort))
            if stop is not None
            else None
        )
        try:
            await self._cleanup.run()
            await self._finalizer.finalize()
            await self._run_one_step(abort)
        except WorkerAborted:
            logger.warning("tick aborted mid-step — stop signal or lost lock")
        finally:
            heartbeat.cancel()
            with suppress(asyncio.CancelledError):
                await heartbeat
            if stop_watch is not None:
                stop_watch.cancel()
                with suppress(asyncio.CancelledError):
                    await stop_watch
            await self._lock.release(LOCK_KEY, token)

    @staticmethod
    async def _mirror_stop(stop: asyncio.Event, abort: asyncio.Event) -> None:
        """Set this tick's abort once the process stop signal fires, so an
        in-flight drain stops at the next ``check_abort`` rather than running to
        completion. Cancelled in the tick's finally when the tick ends first."""
        await stop.wait()
        abort.set()

    async def _run_one_step(self, abort: asyncio.Event) -> None:
        """Drain the FIRST heavy step that has work: scan, else enrich, else
        scrape. Backlog (scan/enrich) is preferred over fresh ingest (scrape)."""
        if await self._scanner.drain(abort):
            return
        if await self._enricher.drain(abort):
            return
        await self._scrape_step(abort)

    async def _scrape_step(self, abort: asyncio.Event) -> bool:
        """Drain the scrape ingest: while the system run cap is not reached and a
        gym is due, open a run and scrape it (leaving 'running' + 'pending' rows).
        Bounded by the rolling per-gym + system run caps. A due gym with an
        in-flight run is never re-selected, so the drain advances through gyms."""
        did_any = False
        while True:
            check_abort(abort)
            if await self._system_cap_reached():
                logger.info("system run cap reached — stopping scrape drain")
                break
            gym_id = await self._select_gym()
            if gym_id is None:
                break
            await self._scrape_gym(gym_id)
            did_any = True
        return did_any

    async def _scrape_gym(self, gym_id: str) -> None:
        """One gym's scrape: load spec → open a run → scrape the pool → funnel
        candidates → carry-forward + write them as 'pending'. Logs the scrape
        cost. Does NOT enrich, scan, or complete the run — the sweeps + finalizer
        take it from here."""
        spec = await self._spec.load(gym_id)
        run_id = await self._start_run(gym_id)
        scrape = await self._scraper.scrape(spec)
        funnel = await self._funnel.select(spec)
        await self._scraper.write_feed(spec, run_id, funnel.candidate_ids)
        await self._cost_log.log_scrape(
            gym_id,
            run_id,
            youtube_quota_units=scrape.youtube_quota_units,
            embed_usd=funnel.embed_usd,
        )

    async def _heartbeat(self, token: UUID, abort: asyncio.Event) -> None:
        """Renew the lease every interval; on a lost lease set the abort flag."""
        while True:
            await asyncio.sleep(settings.worker_heartbeat_seconds)
            renewed = await self._lock.renew(
                LOCK_KEY, token, ttl_seconds=settings.worker_lock_ttl_seconds
            )
            if not renewed:
                logger.error("heartbeat lost the lock — aborting tick")
                abort.set()
                return

    async def _system_cap_reached(self) -> bool:
        """True when runs started across all gyms in the rolling window already
        reach the system-wide cap (the global YouTube-quota / Apify budget guard)."""
        row = await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_system_run_count.sql"),
            {"cap_window_hours": settings.worker_cap_window_hours},
        )
        count = int(row["runs_in_window"]) if row else 0
        return count >= settings.worker_system_run_cap

    async def _select_gym(self) -> str | None:
        """Derive the highest-priority DUE gym under its per-gym run cap (and with
        no in-flight run), or None when nothing is due."""
        row = await self._db.execute_with_retry(
            load_sql(SQL_DIR / "worker_select_due_gym.sql"),
            {
                "cap_window_hours": settings.worker_cap_window_hours,
                "gym_run_cap": settings.worker_gym_run_cap,
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
