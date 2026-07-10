"""Tick step — finalize every 'running' run to completed or failed.

Runs after cleanup, before the heavy step. Because runs are now long-lived (a run
stays 'running' across ticks while the enrich + scan sweeps chew through its
pending rows), a separate step decides when a run is done, purely from the feed
rows it owns — no in-memory run bookkeeping, so crash recovery is free.

Two SQL passes, in this ORDER (completion beats the TTL fail):
  1. complete — a run whose terminal (accepted/rejected) fraction of ALL its feed
     rows reaches ``worker_run_complete_fraction``.
  2. fail — a run with ZERO feed rows older than ``worker_zero_row_grace_hours``
     ('no feed rows'), else a run older than ``worker_run_ttl_hours`` that never
     reached the completion fraction ('run ttl exceeded').
"""

from __future__ import annotations

import logging
from pathlib import Path

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


class WorkerFinalizer:
    """Completes / fails 'running' runs from their feed rows each tick."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def finalize(self) -> None:
        """Complete sufficiently-judged runs, then fail empty / stuck ones."""
        completed = await self._complete()
        failed = await self._fail()
        if completed or failed:
            logger.info(
                "finalize: %d completed, %d failed", completed, failed
            )

    async def _complete(self) -> int:
        async with self._db.session() as session:
            result = await session.execute(
                text(load_sql(SQL_DIR / "worker_finalize_complete.sql")),
                {"complete_fraction": settings.worker_run_complete_fraction},
            )
            count = result.rowcount
            await session.commit()
        return count

    async def _fail(self) -> int:
        async with self._db.session() as session:
            result = await session.execute(
                text(load_sql(SQL_DIR / "worker_finalize_fail.sql")),
                {
                    "zero_row_grace_hours": settings.worker_zero_row_grace_hours,
                    "run_ttl_hours": settings.worker_run_ttl_hours,
                },
            )
            count = result.rowcount
            await session.commit()
        return count
