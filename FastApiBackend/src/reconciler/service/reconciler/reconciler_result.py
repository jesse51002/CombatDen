"""Structured result models for a reconciler run.

Each step-service returns a ``SweepResult`` so the orchestrator can log a
compact, machine-readable summary of one run. These are internal telemetry
models, not an API response.

``SweepResult`` itself lives in ``src/shared/sweep_result.py`` (re-exported here
for the existing reconciler call sites) so the memberships invoice-fetch service
can share it without importing from ``reconciler``.
"""

from pydantic import BaseModel, Field

from src.shared.sweep_result import SweepResult

__all__ = ["ReconcilerRunResult", "SweepResult"]


class ReconcilerRunResult(BaseModel):
    """The outcome of one full reconciler run."""

    sweeps: list[SweepResult] = Field(default_factory=list)
