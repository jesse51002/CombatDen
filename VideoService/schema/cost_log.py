"""The cost log — an append-only ledger of every cost-bearing pipeline run.

Lives at ``apps/<app_id>/cost_log.yaml`` as an **ever-growing YAML sequence**:
each pipeline step appends one :class:`CostEntry` when it runs, recording which
step it was (:class:`ExecutionType`) and a breakdown of what it spent. Append-only
by design — a running ledger, never overwritten — so spend stays auditable across
every run and step.
"""

from __future__ import annotations

import enum
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ExecutionType(str, enum.Enum):
    """Which pipeline step a cost entry came from."""

    SEARCH = "search"  # Apify search (videos + channel avatar + inline transcript)
    TRANSCRIPT = "transcript"  # standalone transcript scraper (Apify)
    TAG = "tag"  # pool tagging: gym_type + genre, gym-agnostic (LLM)
    SCAN = "scan"  # per-gym scan: is_good verdicts against gym specs (LLM)


class CostEntry(BaseModel):
    """One cost-bearing run's spend, appended to the ledger when the step ends."""

    model_config = ConfigDict(extra="forbid")

    execution_type: ExecutionType
    at: datetime  # when the run completed (UTC)
    # Cost components in USD, e.g. {"llm_usd": 0.0123} or {"apify_usd": 0.18}.
    breakdown: dict[str, float] = Field(default_factory=dict)
    # Free context: gyms scanned, video/query counts, model — whatever helps audit.
    note: str | None = None

    @property
    def total_usd(self) -> float:
        """Sum of the breakdown — the entry's total spend."""
        return sum(self.breakdown.values())
