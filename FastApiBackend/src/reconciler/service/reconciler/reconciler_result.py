"""Structured result models for a reconciler run.

Each step-service returns a ``SweepResult`` so the orchestrator can log a
compact, machine-readable summary of one run. These are internal telemetry
models, not an API response.
"""

from pydantic import BaseModel, Field


class SweepResult(BaseModel):
    """The outcome of one step-service over a single reconciler run."""

    name: str
    processed: int = 0  # rows / members / objects examined
    changed: int = 0  # acted on (deleted / cancelled / absorbed)
    skipped: int = 0  # intentionally left (e.g. family lock held)
    errors: int = 0  # per-item failures that did not abort the sweep


class ReconcilerRunResult(BaseModel):
    """The outcome of one full reconciler run."""

    sweeps: list[SweepResult] = Field(default_factory=list)
