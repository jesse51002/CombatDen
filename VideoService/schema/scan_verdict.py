"""The structured verdict the **per-gym scan** pass gets back from the model.

One LLM call per (gym, candidate pool video) returns this: whether the video
belongs in THIS gym's feed, judged against the gym's own specifications. The same
pool video can be good for one gym and rejected by another — approval is a
per-gym verdict, never a pool property. The scan sorts each candidate into the
gym's ``good_video_ids`` / ``rejected_video_ids`` accordingly.

``extra="forbid"`` so a malformed reply is rejected and re-asked by
``complete_structured``.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ScanVerdict(BaseModel):
    """The model's keep/drop verdict for one video against one gym's specs."""

    model_config = ConfigDict(extra="forbid")

    # Does this video belong in THIS gym's feed? True -> good_video_ids,
    # False -> rejected_video_ids. Judged against the gym's specifications.
    is_good: bool
