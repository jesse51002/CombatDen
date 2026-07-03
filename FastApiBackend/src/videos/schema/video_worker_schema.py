"""Pydantic schemas for the video-worker control surface.

The backend does not run the worker — it only enqueues gyms onto the Postgres
``video_worker_queue`` and reports run/queue state. ``WorkerRunQueuedResponse``
is the 202 body of the manual-run endpoint; ``VideoWorkerStatusResponse`` is the
status endpoint's read projection.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict
from schema.video import VideoRunStatus


class WorkerRunQueuedResponse(BaseModel):
    """202 body for a manual worker-run request — the gym is now queued."""

    model_config = ConfigDict(extra="forbid")

    queued: bool = True


class VideoWorkerStatusResponse(BaseModel):
    """A gym's video-worker state in one read.

    ``last_updated`` is when the gym's feed was last refreshed (the newest
    COMPLETED run's ``finished_at``), NULL when no run has completed yet.
    ``queued`` / ``running`` reflect pending + in-flight work.
    ``last_run_status`` is the most-recent run's status (by ``created_at``),
    NULL when the gym has never had a run.
    """

    model_config = ConfigDict(extra="forbid")

    last_updated: datetime | None = None
    queued: bool = False
    running: bool = False
    last_run_status: VideoRunStatus | None = None
