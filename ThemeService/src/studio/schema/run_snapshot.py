"""RunSnapshot — the whole state of one run, as a single response.

The poll fallback for a client that can't (or doesn't want to) hold an SSE
connection: exactly the same records the stream carries, plus the derived
status. ``GET /runs/{id}`` and ``GET /runs/{id}/events`` therefore never
disagree — one builds the other's list in one shot.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from src.studio.schema.run_record import RunRecord
from src.studio.schema.run_status import RunStatus


class RunSnapshot(BaseModel):
    """One run's identity, status, and its full record list so far."""

    model_config = ConfigDict(extra="forbid")

    run_id: str
    app_id: str
    # The run folder's name under `apps/<app_id>/` — what the read API calls
    # its `run_id`, and what a client uses to fetch the finished theme.
    run_name: str
    status: RunStatus
    started_at: str
    finished_at: str | None = None
    error: str | None = None
    records: list[RunRecord]
