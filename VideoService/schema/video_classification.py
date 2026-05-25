"""The structured verdict the classification pass gets back from the model.

One LLM call per video returns this: whether the video belongs in the company's
feed (``is_good``) and the single content genre it actually is (``tag``).
``extra="forbid"`` so a malformed reply is rejected and re-asked by
``complete_structured`` rather than silently accepted.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema.video_type import VideoType


class VideoClassification(BaseModel):
    """The model's per-video verdict: keep/drop and genre."""

    model_config = ConfigDict(extra="forbid")

    # Does this video belong in the company's feed? False for off-niche content
    # or anything matching the brief's avoid_desc — kept, not dropped.
    is_good: bool
    # The video's single content genre, judged from its actual title /
    # description / runtime (not the search that surfaced it).
    tag: VideoType
