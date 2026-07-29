"""What the brief agent can emit — the three arms of its output union.

One tight unit: the two structured outputs plus the union that names them.
The agent has no tools, so this union is its *entire* vocabulary — it either
says something, asks something, or proposes the finished brief.

The brief itself is never redefined here. ``BriefProposal.brief`` is the real
contract, ``schema/customization.py`` — five fields, ``extra="forbid"``, with
the non-empty validators on all of them — so a proposal that invents a sixth
field cannot be produced, and one with a blank field cannot be parsed.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema import Customization

# A chip row wider than this stops being a choice and starts being a list; two
# is the minimum that makes it a choice at all.
MIN_QUESTION_OPTIONS = 2
MAX_QUESTION_OPTIONS = 6


class AgentQuestion(BaseModel):
    """A multiple-choice question, rendered as selectable chips.

    The browser shows ``options`` as chips (single-select unless
    ``multi_select``); whatever the owner picks becomes the next turn's
    ``message``. This is the agent's default way to ask — plain text is
    reserved for genuinely open-ended questions (the gym's name) and short
    acknowledgements.
    """

    model_config = ConfigDict(extra="forbid")

    question: str
    options: list[str] = Field(
        min_length=MIN_QUESTION_OPTIONS, max_length=MAX_QUESTION_OPTIONS
    )
    multi_select: bool = False


class BriefProposal(BaseModel):
    """The finished proposal: a chat ``message`` AND the ``brief`` itself.

    The agent must ALWAYS pair a proposed brief with a short conversational
    message — the browser appends the message to the chat while the five
    fields show in a highlighted review panel, so **a proposal is never
    silent**.
    """

    model_config = ConfigDict(extra="forbid")

    message: str = Field(
        min_length=1,
        description=(
            "A short chat message accompanying the proposal — what you put "
            "together, and an invitation to review and accept it or say what "
            "to change."
        ),
    )
    brief: Customization


# Free text (the next question or a quick acknowledgement), a multiple-choice
# question, or the finished proposal. Nothing else: the agent has zero tools.
BriefAgentOutput = str | BriefProposal | AgentQuestion
