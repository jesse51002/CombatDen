"""VideosWorkerStatusService — a read-only window into the background worker.

The backend does not run or schedule the worker, and there is no queue: the
VideoService worker process derives which gym to run each tick from run / spec /
curation timestamps, and writes ``video_run`` rows. This service only *reports*
a gym's run state (last feed refresh, whether a run is in flight, the last run's
outcome) for the CRM to display. Nothing here triggers a run.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_worker_schema import VideoWorkerStatusResponse


class VideosWorkerStatusService:
    """Read a gym's background-worker run state."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def status(self, gym_id: UUID) -> VideoWorkerStatusResponse:
        """The gym's worker state (last-refresh time, running, last run status).

        A gym with no runs yet returns ``last_updated=None`` and
        ``last_run_status=None``; ``running`` reflects an in-flight run.
        """
        sql = load_sql(SQL_DIR / "videos_worker_status.sql")
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .fetchone()
            )
        return VideoWorkerStatusResponse.model_validate(dict(row))
