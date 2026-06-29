"""Pydantic schemas for the video spec domain.

``VideoSpecDraft`` is the conversational agent's structured output — criteria only
(disciplines + keep/avoid descriptions). Queries are generated deterministically by
``VideoQueryGenerator`` after the owner accepts the draft; the agent never sees or
authors them.  ``VideoSpecView`` is the read projection of a gym's LATEST spec
version (includes queries, source, created_at).  ``QueriesResult`` is the internal
structured output of the single-call query generator.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
from schema.video import GymVideoSpecSource

from src.videos.schema.videos_gym_type import GymType

# Default number of search queries generated per spec commit.
DEFAULT_QUERY_COUNT = 24


class VideoSpecDraft(BaseModel):
    """A proposed video spec — the agent's structured output.

    Contains ONLY the criteria fields (disciplines + keep/avoid descriptions).
    Search queries are generated separately by ``VideoQueryGenerator`` after the
    owner accepts this draft and are never authored by the agent.  A new
    ``gym_video_spec`` version (``source='admin_update'``) is appended only when
    the criteria differ from the gym's current spec.
    """

    model_config = ConfigDict(extra="forbid")

    disciplines: list[GymType] = Field(
        min_length=1,
        description=(
            "The gym's fitness discipline(s) from the fixed vocabulary; the first "
            "is the primary one. Drives which slice of the video pool is scanned."
        ),
    )
    videos_desc: str = Field(
        min_length=2,
        description=(
            "The KEEP criteria: a thorough description of the videos this gym "
            "wants in its feed — topics, styles, level, vibe. This is what the "
            "scan judges candidates against, so be concrete and specific."
        ),
    )
    avoid_desc: str = Field(
        min_length=2,
        description=(
            "The AVOID criteria: what must NOT appear — off-brand topics, wrong "
            "disciplines, low quality, anything that would dilute the feed."
        ),
    )
    short_videos_desc: str | None = Field(
        default=None,
        description="A one-line display summary of the keep criteria (optional).",
    )
    short_avoid_desc: str | None = Field(
        default=None,
        description="A one-line display summary of the avoid criteria (optional).",
    )


class VideoSpecView(BaseModel):
    """The latest spec version for a gym (read from ``gym_video_spec_latest``)."""

    model_config = ConfigDict(extra="ignore")

    gym_id: UUID
    disciplines: list[str]
    videos_desc: str
    avoid_desc: str
    short_videos_desc: str | None = None
    short_avoid_desc: str | None = None
    queries: list[str]
    source: GymVideoSpecSource
    imported_from: str | None = None
    created_at: datetime


class QueriesResult(BaseModel):
    """Internal structured output of the single-call query generator."""

    model_config = ConfigDict(extra="forbid")

    queries: list[str] = Field(
        description=(
            "Concrete YouTube search phrases spread across the video genres."
        ),
    )
