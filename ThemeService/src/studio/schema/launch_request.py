"""LaunchRequest / LaunchAccepted — the POST that starts a run.

One tight unit: what a launch asks for and what it immediately gets back.
The POST does **not** block until generation completes — a full run is
minutes and real money — so it returns a run id the caller then watches via
``GET /runs/{id}/events`` (or polls with ``GET /runs/{id}``).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, model_validator

from schema import Customization, PathSegment
from src.studio.schema.run_status import RunStatus


class LaunchRequest(BaseModel):
    """Which app, what to call the run, and the brief to run it from.

    The brief arrives one of exactly two ways, never both and never
    neither:

    - ``brief`` — the full ``Customization`` inline (the form's own commit
      already validated it; this is the one-shot path),
    - ``brief_slug`` — the stem of a brief already saved under
      ``.studio/briefs/`` by ``POST /briefs``.

    ``run_name`` names a **new** folder under ``apps/<app_id>/``. The launch
    path never targets an existing run, so the pipeline's destructive
    in-place overwrite is unreachable from a browser.
    """

    model_config = ConfigDict(extra="forbid")

    app_id: str
    run_name: PathSegment
    brief: Customization | None = None
    brief_slug: PathSegment | None = None

    @model_validator(mode="after")
    def _exactly_one_brief_source(self) -> LaunchRequest:
        if (self.brief is None) == (self.brief_slug is None):
            raise ValueError(
                "provide exactly one of 'brief' (inline) or 'brief_slug' "
                "(a brief saved by POST /briefs)"
            )
        return self


class LaunchAccepted(BaseModel):
    """The immediate answer: the run exists and is going."""

    model_config = ConfigDict(extra="forbid")

    run_id: str
    app_id: str
    run_name: str
    status: RunStatus
    started_at: str
