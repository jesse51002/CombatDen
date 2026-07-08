"""The legacy cost log — the append-only YAML ledger read once at cutover.

Lived at ``cost_log.yaml`` as an **ever-growing YAML sequence**: each pipeline
step appended one :class:`CostEntry` when it ran, recording which step it was
(:class:`~schema.cost.CostStage`) and a breakdown of what it spent. Only the
one-time cutover import script (``scripts/import_yaml/run.py``) still reads
this shape now — the live worker writes the SQL ``cost_log`` table directly
(see ``src/worker/worker_cost_log.py``).
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from schema.cost import CostStage


class CostEntry(BaseModel):
    """One cost-bearing run's spend, as recorded in the legacy YAML ledger."""

    model_config = ConfigDict(extra="forbid")

    execution_type: CostStage
    at: datetime  # when the run completed (UTC)
    # Cost components in USD, e.g. {"llm_usd": 0.0123} or {"apify_usd": 0.18}.
    breakdown: dict[str, float] = Field(default_factory=dict)
    # Free context: gyms scanned, video/query counts, model — whatever helps audit.
    note: str | None = None

    @property
    def total_usd(self) -> float:
        """Sum of the breakdown — the entry's total spend."""
        return sum(self.breakdown.values())
