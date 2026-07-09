"""Tick step — delete videos that hit the hard-error strike ceiling.

Runs FIRST every tick (before finalize) so the finalize step's terminal-fraction
denominators reflect the shrunk feed. A video's ``failure_count`` is bumped by the
enrich / scan sweeps on a hard error and reset to 0 on success; once it reaches
``worker_failure_max`` the video is unusable and is dropped from the pool. The FK
cascades remove its feed rows, its ``video_rag`` row, and any member recs.
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


class WorkerCleanup:
    """Deletes strike-maxed videos at the top of each tick."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def run(self) -> int:
        """Delete every video at or above the strike ceiling; return the count."""
        async with self._db.session() as session:
            result = await session.execute(
                text(load_sql(SQL_DIR / "worker_cleanup_videos.sql")),
                {"max_failures": settings.worker_failure_max},
            )
            deleted = result.mappings().all()
            await session.commit()
        if deleted:
            logger.info(
                "cleanup deleted %d strike-maxed video(s)", len(deleted)
            )
        return len(deleted)
