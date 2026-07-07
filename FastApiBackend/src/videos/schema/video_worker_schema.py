"""Pydantic schemas for the video-worker status surface.

The backend does not run or schedule the worker — the VideoService worker
derives its own work from run/spec/curation timestamps (no queue). This module
holds only the read projection the CRM shows: ``VideoWorkerStatusResponse``.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict
from schema.video import VideoRunStatus


class VideoWorkerStatusResponse(BaseModel):
    """A gym's video-worker state in one read.

    ``last_updated`` is when the gym's feed was last refreshed (the newest
    COMPLETED run's ``finished_at``), NULL when no run has completed yet.
    ``running`` reflects an in-flight run. ``last_run_status`` is the most-recent
    run's status (by ``created_at``), NULL when the gym has never had a run.
    """

    model_config = ConfigDict(extra="forbid")

    last_updated: datetime | None = None
    running: bool = False
    last_run_status: VideoRunStatus | None = None
