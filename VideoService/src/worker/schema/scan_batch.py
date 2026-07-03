"""The structured verdict the worker's batched keep/drop scan call returns.

One scan call judges a BATCH of candidate videos against the gym's
videos_desc / avoid_desc, returning one ``is_good`` per video keyed by its
``video_id``. Batching (vs one call per video) is the cost lever — a run scans
up to ``scan_budget_per_run`` candidates.

``extra="forbid"`` on both models so a malformed reply is rejected and re-asked.
The caller validates that the returned ids are a subset of the batch's ids
(hallucinated ids are dropped) and that every batch id got a verdict (a missing
id is retried once, then defaulted to rejected).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ScanVerdictItem(BaseModel):
    """One video's keep/drop verdict within a batch."""

    model_config = ConfigDict(extra="forbid")

    video_id: str
    is_good: bool


class ScanBatchResult(BaseModel):
    """The model's verdicts for one batch of candidate videos."""

    model_config = ConfigDict(extra="forbid")

    verdicts: list[ScanVerdictItem]
