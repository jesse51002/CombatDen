"""Studio error vocabulary (kept apart from `core.errors` and `api.errors`).

One exception per refusal the launch path can make, so the router maps a
cause to a status code instead of inspecting messages.
"""

from __future__ import annotations


class StudioError(Exception):
    """Base for every studio refusal."""


class UnknownAppError(StudioError):
    """No such `apps/<app_id>/app.yaml` (maps to HTTP 404)."""


class UnknownBriefError(StudioError):
    """No such saved brief under `.studio/briefs/` (maps to HTTP 404)."""


class UnknownRunError(StudioError):
    """No such run, in memory or on disk (maps to HTTP 404)."""


class RunInFlightError(StudioError):
    """A run is already going and runs are serialized (maps to HTTP 409).

    Carries the active run's identity so the UI can say *which* one, rather
    than a bare "busy".
    """

    def __init__(self, run_id: str, app_id: str, run_name: str) -> None:
        super().__init__(
            f"run {run_id} is already in flight ({app_id}/{run_name}); "
            "the providers rate-limit, so the studio runs one at a time"
        )
        self.run_id = run_id
        self.app_id = app_id
        self.run_name = run_name


class RunNameTakenError(StudioError):
    """The target run directory already exists (maps to HTTP 409).

    The launch path only ever CREATES run directories — it never targets an
    existing one — so the destructive in-place overwrite is unreachable from
    the browser. A collision is refused, not overwritten.
    """
