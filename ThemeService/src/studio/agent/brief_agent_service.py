"""BriefAgentService — one conversational turn with the brief interviewer.

The agent does ONLY the conversation. It has **zero tools** and cannot write
anything: it converses to propose a ``Customization``, ask a multiple-choice
``AgentQuestion``, or reply in plain text. Committing is deterministic code
outside it — when the browser sends ``accepted_brief``, this service calls
``BriefService.commit``, the same validate-and-write path the plain form
posts to, so there is exactly one place that decides what a valid brief is
and where it goes.

The ``Agent`` is built on construction from an explicit ``AnthropicModel`` +
``AnthropicProvider``, so the key comes straight from settings and never from
``os.environ``. **When the key is empty the agent is simply not built**: the
studio boots, launches runs and commits form briefs exactly as before, and
only this one endpoint fails (``LookupError`` -> 503). That is deliberate —
an unconfigured optional feature must not take the app down with it.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from pydantic_ai import Agent
from pydantic_ai.agent import AgentRunResult
from pydantic_ai.messages import ModelMessagesTypeAdapter
from pydantic_ai.models.anthropic import AnthropicModel
from pydantic_ai.providers.anthropic import AnthropicProvider

from schema import Customization, PathSegment
from src.core.config import settings as pipeline_settings
from src.studio.config import settings
from src.studio.schema.agent_output import (
    AgentQuestion,
    BriefAgentOutput,
    BriefProposal,
)
from src.studio.schema.agent_turn import AgentTurnRequest, AgentTurnResponse
from src.studio.schema.brief_request import BriefCommitted, BriefRequest
from src.studio.service.brief_service import BriefService, brief_service

logger = logging.getLogger(__name__)

SYSTEM_PROMPT_PATH = Path(__file__).parent / "prompts" / "brief_agent_system.md"

# The opening turn carries no message — the browser just says "go". A note
# rather than an empty prompt, which the provider would reject.
OPENING_NOTE = "[Start the brief interview.]"
# Bracketed like the opening note so the agent reads these as system asides,
# not as something the owner typed.
SAVED_NOTE = "[The proposed brief has been saved as {slug}.yaml.]"
# Used only when the post-save agent call fails. The save already succeeded,
# so the turn must still report it rather than surfacing an error.
SAVED_FALLBACK_REPLY = "The brief has been saved."

_USAGE_FIELDS = ("requests", "input_tokens", "output_tokens", "total_tokens")


class BriefAgentService:
    """Runs one turn of the brand-brief interview.

    ``BriefService`` is the only collaborator: the accept path commits
    through it. Nothing else is injected because the agent needs nothing
    else — it has no tools, and a brand-new brief has no prior state to seed.
    """

    def __init__(
        self,
        *,
        briefs: BriefService,
        model_name: str,
        retries: int,
        anthropic_api_key: str,
    ) -> None:
        self._briefs = briefs
        self._agent: Agent[None, BriefAgentOutput] | None = None
        if anthropic_api_key:
            self._agent = self._build_agent(model_name, retries, anthropic_api_key)
        else:
            logger.warning(
                "brief agent not built: ANTHROPIC_API_KEY is empty. The rest "
                "of the studio is unaffected; POST /brief-agent will 503."
            )

    @staticmethod
    def _build_agent(
        model_name: str, retries: int, anthropic_api_key: str
    ) -> Agent[None, BriefAgentOutput]:
        """The agent, with the system prompt read from its ``.md`` and no tools."""
        provider = AnthropicProvider(api_key=anthropic_api_key)
        model = AnthropicModel(model_name, provider=provider)
        return Agent(
            model,
            output_type=[str, BriefProposal, AgentQuestion],
            instructions=SYSTEM_PROMPT_PATH.read_text(encoding="utf-8"),
            retries=retries,
        )

    async def turn(self, request: AgentTurnRequest) -> AgentTurnResponse:
        """Run one turn: converse, or commit-then-acknowledge.

        **Accept path** (``request.accepted_brief`` is set): commit FIRST via
        ``BriefService``, then run the agent on a short outcome note so it can
        acknowledge and invite further changes. Returns ``saved=True``.

        **Normal turn**: hand the message to the agent and map whichever of
        the three outputs it produced. Returns ``saved=False``.

        Raises ``LookupError`` when no API key is configured.
        """
        agent = self._agent
        if agent is None:
            raise LookupError(
                "The brief agent is not configured: ANTHROPIC_API_KEY is "
                "empty. Set it in .env to use the conversational interview; "
                "POST /briefs (the plain form) works without it."
            )

        history = (
            ModelMessagesTypeAdapter.validate_python(request.history)
            if request.history
            else None
        )

        accepted = request.accepted_brief
        if accepted is not None:
            return await self._handle_accept(
                agent, accepted, request.slug, history, request.history or []
            )
        return await self._handle_turn(agent, request.message, history)

    # --- the two paths ----------------------------------------------------

    async def _handle_accept(
        self,
        agent: Agent[None, BriefAgentOutput],
        accepted: Customization,
        slug: PathSegment | None,
        history: object,
        raw_history: list[Any],
    ) -> AgentTurnResponse:
        """Commit the accepted brief, then let the agent acknowledge it.

        The commit runs first and on its own: if it raises (a blank field, a
        design name with nothing sluggable in it) nothing was written and the
        error surfaces as a 422, unchanged.

        Once it succeeds the brief is on disk, so a failure in the *follow-up*
        agent call must not be reported as a failed save — the turn degrades
        to a fixed acknowledgement with ``saved=True`` instead of propagating.
        """
        committed = await self._briefs.commit(
            BriefRequest.from_brief(accepted, slug)
        )
        note = SAVED_NOTE.format(slug=committed.slug)

        try:
            result = await agent.run(note, message_history=history)
        except Exception:
            logger.exception(
                "brief %s was saved but the post-save agent call failed",
                committed.slug,
            )
            return AgentTurnResponse(
                reply=SAVED_FALLBACK_REPLY,
                history=raw_history,
                saved=True,
                committed=committed,
            )
        return self._respond(result, saved=True, committed=committed)

    @classmethod
    async def _handle_turn(
        cls,
        agent: Agent[None, BriefAgentOutput],
        message: str,
        history: object,
    ) -> AgentTurnResponse:
        """A plain conversational turn."""
        # Only the opening turn can be blank; AgentTurnRequest enforces that.
        prompt = message.strip() or OPENING_NOTE
        result = await agent.run(prompt, message_history=history)
        return cls._respond(result, saved=False, committed=None)

    # --- shared mapping ---------------------------------------------------

    @classmethod
    def _respond(
        cls,
        result: AgentRunResult[BriefAgentOutput],
        *,
        saved: bool,
        committed: BriefCommitted | None,
    ) -> AgentTurnResponse:
        """One run result as the wire response.

        Both paths map output the same way, so a post-save proposal or
        question surfaces properly instead of being flattened to reply-only.
        A proposal fills ``reply`` AND ``draft``; the other two fill exactly
        one field.
        """
        output = result.output
        if isinstance(output, BriefProposal):
            reply, draft, question = output.message, output.brief, None
        elif isinstance(output, AgentQuestion):
            reply, draft, question = None, None, output
        else:  # plain text
            reply, draft, question = output, None, None
        return AgentTurnResponse(
            reply=reply,
            draft=draft,
            question=question,
            history=ModelMessagesTypeAdapter.dump_python(
                result.all_messages(), mode="json"
            ),
            saved=saved,
            committed=committed,
            usage=cls._usage_dict(result.usage),
        )

    @staticmethod
    def _usage_dict(usage: Any) -> dict[str, int]:
        """The token counts this run reported, skipping any it didn't."""
        return {
            key: getattr(usage, key)
            for key in _USAGE_FIELDS
            if getattr(usage, key, None) is not None
        }


_service: BriefAgentService | None = None


def brief_agent_service() -> BriefAgentService:
    """The process-wide brief agent (it holds one built ``Agent``).

    The model name and retries are studio config; the API key comes from
    ``src.core.config`` — the pipeline settings the studio already imports —
    so this one secret keeps a single definition and a single env var.
    """
    global _service
    if _service is None:
        _service = BriefAgentService(
            briefs=brief_service(),
            model_name=settings.brief_agent_model,
            retries=settings.brief_agent_retries,
            anthropic_api_key=pipeline_settings.anthropic_api_key,
        )
    return _service
