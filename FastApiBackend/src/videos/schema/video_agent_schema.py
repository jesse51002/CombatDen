"""Pydantic schemas and type aliases for the video agent endpoints."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from src.videos.schema.video_spec_schema import VideoSpecDraft


class AgentQuestion(BaseModel):
    """A multiple-choice question the agent asks the owner. The CRM renders the
    ``options`` as selectable chips (single-select unless ``multi_select``); the
    owner's selection becomes the next turn's ``message``."""

    model_config = ConfigDict(extra="forbid")

    question: str
    options: list[str] = Field(min_length=2, max_length=6)
    multi_select: bool = False


class SpecProposal(BaseModel):
    """The agent's finished proposal: a chat ``message`` AND the criteria ``draft``.

    The agent must ALWAYS pair a proposed spec with a short conversational
    ``message`` — the CRM appends the message to the chat while the criteria show
    in the highlighted proposed-spec panel, so a proposal is never silent.
    ``draft`` is criteria-only (no queries)."""

    model_config = ConfigDict(extra="forbid")

    message: str = Field(
        min_length=1,
        description=(
            "A short chat message accompanying the proposal — what you put "
            "together and an invitation to review/accept or request changes."
        ),
    )
    draft: VideoSpecDraft


# The agent outputs free text (its next message), a multiple-choice question, OR a
# finished proposal (a chat message + the criteria draft).
VideoAgentOutput = str | SpecProposal | AgentQuestion


class AgentTurnRequest(BaseModel):
    """One conversational turn.

    ``history`` is the serialized message history the client got back from the
    previous turn (the server holds no session state).  ``message`` may be empty
    for an opening turn (the backend seeds current-state context automatically).
    ``accepted_spec`` is sent by the frontend when the owner presses Accept — the
    agent then saves (or detects no change) and acknowledges.
    """

    model_config = ConfigDict(extra="forbid")

    message: str = Field(default="")
    history: list[Any] | None = None
    accepted_spec: VideoSpecDraft | None = None


class AgentTurnResponse(BaseModel):
    """The agent's turn result: a free-text ``reply``, a multiple-choice
    ``question`` (rendered as chips), OR a finished ``draft`` to review — exactly
    one is set — plus the new serialized ``history`` to send back on the next
    turn.  ``saved`` is True when this turn processed an
    ``accepted_spec`` (whether or not a new version was written — the agent always
    replies); the conversation remains open after a save."""

    reply: str | None = None
    draft: VideoSpecDraft | None = None
    question: AgentQuestion | None = None
    history: list[Any]
    saved: bool = False
    usage: dict[str, Any] | None = None
