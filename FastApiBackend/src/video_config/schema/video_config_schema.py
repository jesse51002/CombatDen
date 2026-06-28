"""Pydantic schemas for the video-config domain.

``VideoConfigDraft`` is dual-purpose: it is the conversational agent's structured
output AND the body of the confirm/save (``PUT``) endpoint — one model, so the
field descriptions double as the LLM's output contract. ``VideoConfigView`` is the
read projection of a gym's LATEST spec version. ``QueriesResult`` is the internal
structured output of the single-call query generator.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
from schema.video import GymVideoSpecSource

from src.videos.schema.videos_gym_type import GymType

# The agent and the standalone endpoint default to this many search queries when
# the caller doesn't specify a count.
DEFAULT_QUERY_COUNT = 24


class VideoConfigDraft(BaseModel):
    """A proposed video config — the agent's structured output and the save body.

    Nothing is written until the owner confirms this draft via the save endpoint;
    saving appends a new ``gym_video_spec`` version (``source='admin_update'``).
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
    queries: list[str] = Field(
        default_factory=list,
        description=(
            "Concrete YouTube search phrases that feed the scrape, spread across "
            "the video genres (how-to/educational through entertainment/clips). "
            "Each is a real search a person would type, not a topic label."
        ),
    )


class VideoConfigView(BaseModel):
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


class GenerateQueriesRequest(BaseModel):
    """Body of the standalone query generator. Every field is optional — omitted
    inputs fall back to the gym's current latest spec."""

    model_config = ConfigDict(extra="forbid")

    disciplines: list[GymType] | None = None
    videos_desc: str | None = None
    avoid_desc: str | None = None
    count: int | None = Field(default=None, ge=1, le=100)


class GenerateQueriesResponse(BaseModel):
    """The generated search queries."""

    queries: list[str]


class VideoConfigAgentRequest(BaseModel):
    """One conversational turn. ``history`` is the serialized message history the
    client got back from the previous turn (the server holds no session)."""

    model_config = ConfigDict(extra="forbid")

    message: str = Field(min_length=1)
    history: list[Any] | None = None


class VideoConfigAgentResponse(BaseModel):
    """The agent's turn result: either a free-text ``reply`` (a question / message)
    OR a finished ``draft`` to review and save — plus the new serialized
    ``history`` to send back on the next turn."""

    reply: str | None = None
    draft: VideoConfigDraft | None = None
    history: list[Any]
    usage: dict[str, Any] | None = None
