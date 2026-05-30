"""The structured verdict the **pool tagging** pass gets back from the model.

One LLM call per pooled video returns this: the single content genre the video
is (``tag``) and the disciplines it is relevant to (``gym_type``, a list). Both
are judged from the video's real content (title / description / runtime /
transcript), gym-agnostic — there is NO approval here. Approval (``is_good``) is
a per-gym verdict produced by the separate scan pass (see ``ScanVerdict``).

``extra="forbid"`` so a malformed reply is rejected and re-asked by
``complete_structured`` rather than silently accepted.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema.gym_type import GymType
from schema.video_type import VideoType


class VideoClassification(BaseModel):
    """The model's per-video pool verdict: genre + the disciplines it fits."""

    model_config = ConfigDict(extra="forbid")

    # The video's single content genre, judged from its actual content.
    tag: VideoType
    # Every discipline this video is relevant to (>=1). Routes the video into the
    # candidate slices gyms scan; it is NOT an approval.
    gym_type: list[GymType] = Field(min_length=1)
