"""VideosWorkerControl — enqueue + status for the VideoService background worker.

The backend does not run the worker; it owns the *control seam*. This service
enqueues a gym onto the Postgres ``video_worker_queue`` (the spec-commit seam and
the CRM's manual-run endpoint) and reports a gym's run/queue state. The worker
process (in VideoService) pops the queue and writes ``video_run`` rows.
"""

from __future__ import annotations

from uuid import UUID

from schema.video import VideoWorkerReason
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_worker_schema import VideoWorkerStatusResponse


class VideosWorkerControl:
    """Enqueue a gym for a worker run and read its worker state."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def enqueue(self, gym_id: UUID, reason: VideoWorkerReason) -> None:
        """Enqueue ``gym_id`` for a worker run (idempotent per gym).

        The upsert keeps the OLDEST pending ``requested_at`` on conflict, so a
        gym editing its spec repeatedly cannot starve older requests; an existing
        row's ``reason`` is left unchanged.
        """
        sql = load_sql(SQL_DIR / "videos_worker_enqueue.sql")
        await self._db.execute_with_retry(
            sql,
            {"gym_id": str(gym_id), "reason": reason.value},
        )

    async def status(self, gym_id: UUID) -> VideoWorkerStatusResponse:
        """The gym's worker state (last-refresh time, queued, running, last run).

        A gym with no runs yet returns ``last_updated=None`` and
        ``last_run_status=None`` (queued/running reflect any pending/in-flight
        work).
        """
        sql = load_sql(SQL_DIR / "videos_worker_status.sql")
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .fetchone()
            )
        return VideoWorkerStatusResponse.model_validate(dict(row))
