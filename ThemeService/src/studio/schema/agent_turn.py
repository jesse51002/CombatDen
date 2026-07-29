"""AgentTurnRequest / AgentTurnResponse — one conversational turn, on the wire.

One tight unit: what a turn asks for and what it gets back.

**The server holds no session state.** The client keeps the transcript and
sends it back as ``history`` every turn; the response hands back the new
transcript for the next one. That is why there is no conversation id, no
store, and nothing to expire — the studio can restart mid-interview and the
browser can carry on.

``history`` is Pydantic AI's own serialized message list, deliberately typed
as opaque. Its shape is that library's contract, not ours: it round-trips
through ``ModelMessagesTypeAdapter`` untouched, and re-declaring it here would
be a second, immediately-stale copy of someone else's schema.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, model_validator

from schema import Customization, PathSegment
from src.studio.schema.agent_output import AgentQuestion
from src.studio.schema.brief_request import BriefCommitted


class AgentTurnRequest(BaseModel):
    """One turn: what the owner said, plus the transcript so far.

    ``accepted_brief`` is what the browser sends when the owner presses
    Accept. It carries the reviewed brief back verbatim, and this same
    endpoint then commits it *before* the agent runs again — the save is
    deterministic code, never something the agent is trusted to do.
    ``slug`` optionally names the file; by default it is derived from the
    design name.
    """

    model_config = ConfigDict(extra="forbid")

    # Empty only on the opening turn, where the service supplies the note that
    # starts the interview.
    message: str = ""
    history: list[Any] | None = None
    accepted_brief: Customization | None = None
    slug: PathSegment | None = None

    @model_validator(mode="after")
    def _mid_conversation_turns_carry_a_message(self) -> AgentTurnRequest:
        """Only the opening turn may be blank.

        A blank message part-way through is a client bug — it would reach the
        provider as an empty user prompt. Refused here, where the cause is
        still legible, rather than as a provider error.
        """
        if self.history and self.accepted_brief is None and not self.message.strip():
            raise ValueError(
                "'message' is required once 'history' is non-empty; only the "
                "opening turn may omit it"
            )
        return self


class AgentTurnResponse(BaseModel):
    """The turn's result: exactly one of reply / draft / question.

    - ``reply`` — free text: the agent's next question or an acknowledgement.
      A proposal sets this *too*, to the proposal's own chat message, so the
      brief never lands in the panel without a word in the conversation.
    - ``draft`` — the proposed brief, for the review panel.
    - ``question`` — a multiple-choice question, for the chip row.

    ``history`` is the transcript to send back next turn. ``saved`` is True
    when this turn committed an ``accepted_brief``; ``committed`` then says
    where it landed, so the client can launch a run from that ``slug`` instead
    of re-deriving the filename itself. The conversation stays open after a
    save.
    """

    model_config = ConfigDict(extra="forbid")

    reply: str | None = None
    draft: Customization | None = None
    question: AgentQuestion | None = None
    history: list[Any]
    saved: bool = False
    committed: BriefCommitted | None = None
    usage: dict[str, int] | None = None
