"""The structured verdict the worker's ONE multimodal enrich call returns.

Per pool video, a single vision call (thumbnail image + title/channel/description
+ transcript slice) produces the genre ``tag`` and the ``disciplines`` it is
relevant to (both written onto ``video``), plus a prose ``summary`` that MUST
describe what the thumbnail shows (attire like gi vs no-gi, setting, production
style) and free-shape ``facets``. The summary is then embedded into
``video_rag``.

``extra="forbid"`` so a malformed reply is rejected and re-asked by
``complete_structured_with_cost``'s validate-and-retry loop. ``disciplines`` is
typed as the shared ``GymType`` enum (not raw strings) so an off-vocabulary value
is caught and re-asked, reusing the same vocabulary the retired classify pass used.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema.gym_type import GymType
from schema.video_type import VideoType


class EnrichResult(BaseModel):
    """One video's enrichment: genre + disciplines + summary + facets."""

    model_config = ConfigDict(extra="forbid")

    # The single content genre, judged from content + thumbnail.
    tag: VideoType
    # Every discipline this video is relevant to (>= 1). Written to
    # ``video.disciplines``; routes the video into the slices gyms scan.
    disciplines: list[GymType] = Field(min_length=1)
    # Prose content summary that MUST include what the thumbnail depicts
    # (attire, setting, production style) as well as the content. Embedded.
    summary: str
    # Free-shape structured attributes, e.g. {"gi": false, "setting":
    # "competition", "skill_level": "beginner"}. Stored on ``video_rag``.
    facets: dict[str, str | int | bool] = Field(default_factory=dict)
