"""Pydantic schemas for the video spec domain.

``VideoSpecDraft`` is the conversational agent's structured output — criteria only
(disciplines + keep/avoid descriptions). Queries are generated deterministically by
``VideoQueryGenerator`` after the owner accepts the draft; the agent never sees or
authors them.  ``VideoSpecView`` is the read projection of a gym's LATEST spec
version (includes queries, source, created_at).  ``VideoQueryGenerator`` runs a
two-call flow whose structured outputs are ``LandscapeResult`` (call 1 — the
niche's content landscape) and ``QueriesResult`` (call 2 — the search queries).
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
from schema.video import GymVideoSpecSource

from src.videos.schema.videos_gym_type import GymType


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


class LandscapeResult(BaseModel):
    """Structured output of the landscape-research call (step 1 of query gen).

    The LLM brainstorms the niche's content landscape from its own knowledge:
    popular YouTube channels, well-known creators / athletes / instructors, and
    notable series / events / shows. Hallucination is tolerated by design — a
    wrong name just searches poorly — so nothing here is validated downstream.
    """

    model_config = ConfigDict(extra="forbid")

    channels: list[str] = Field(
        description=(
            "Popular YouTube channels in this niche — each a channel name, "
            "optionally with a 2-4 word descriptor."
        ),
    )
    creators: list[str] = Field(
        description=(
            "Well-known creators / athletes / instructors — each a name, "
            "optionally with a 2-4 word descriptor."
        ),
    )
    series_events: list[str] = Field(
        description=(
            "Notable series / events / shows — each a name, optionally with a "
            "2-4 word descriptor."
        ),
    )


class QueriesResult(BaseModel):
    """Structured output of the query-generation call (step 2 of query gen)."""

    model_config = ConfigDict(extra="forbid")

    queries: list[str] = Field(
        description=(
            "Concrete YouTube search phrases spread across the video genres."
        ),
    )
