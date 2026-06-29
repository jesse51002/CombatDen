"""VideoAgentService — the conversational video-spec agent.

The agent does ONLY the conversation; query generation + saving are deterministic
backend logic outside it.  The agent has ZERO tools — it converses to propose a
``VideoSpecDraft`` (criteria only: disciplines + keep/avoid descriptions), and the
backend's accept-path commits the spec via ``VideosService.save_accepted_spec``
(which runs the diff guard, generates queries, and saves) when the frontend sends
``accepted_spec`` in the request.

Builds the Pydantic AI ``Agent`` on construction using an explicit
``AnthropicModel`` + ``AnthropicProvider`` so the key comes directly from settings,
not from ``os.environ``.  When ``anthropic_api_key`` is empty the agent is not
built and ``agent_turn`` raises ``LookupError`` with a clear message.
"""

from __future__ import annotations

from uuid import UUID

from pydantic_ai import Agent
from pydantic_ai.messages import ModelMessagesTypeAdapter
from pydantic_ai.models.anthropic import AnthropicModel
from pydantic_ai.providers.anthropic import AnthropicProvider

from src.videos import PROMPTS_DIR
from src.videos.schema.video_agent_schema import (
    AgentQuestion,
    AgentTurnRequest,
    AgentTurnResponse,
    SpecProposal,
    VideoAgentOutput,
)
from src.videos.schema.video_spec_schema import VideoSpecDraft
from src.videos.service.videos_service import VideosService

_SYSTEM_PROMPT_PATH = PROMPTS_DIR / "video_agent_system.md"


class VideoAgentService:
    """Runs one conversational turn with the video-spec agent.

    ``VideosService`` is the only external dependency — the accept-path calls
    ``save_accepted_spec`` through it, and the first-turn state seeding calls
    ``load_latest_spec``.  The Pydantic AI agent is built on construction with an
    explicit ``AnthropicModel``; no tools are registered.  If
    ``anthropic_api_key`` is empty the agent is skipped and ``agent_turn`` raises
    ``LookupError``.
    """

    def __init__(
        self,
        *,
        videos_service: VideosService,
        model_name: str,
        retries: int,
        anthropic_api_key: str,
    ) -> None:
        self._videos_service = videos_service
        self._agent: Agent[None, VideoAgentOutput] | None = None
        if anthropic_api_key:
            self._agent = self._build_agent(model_name, retries, anthropic_api_key)

    def _build_agent(
        self,
        model_name: str,
        retries: int,
        anthropic_api_key: str,
    ) -> Agent[None, VideoAgentOutput]:
        """Build the Pydantic AI agent with no tools."""
        provider = AnthropicProvider(api_key=anthropic_api_key)
        pydantic_model = AnthropicModel(model_name, provider=provider)
        system_prompt = _SYSTEM_PROMPT_PATH.read_text(encoding="utf-8")
        return Agent(
            pydantic_model,
            output_type=[str, SpecProposal, AgentQuestion],
            instructions=system_prompt,
            retries=retries,
        )

    async def agent_turn(
        self, gym_id: UUID, request: AgentTurnRequest
    ) -> AgentTurnResponse:
        """Run one conversational turn; return the agent's reply or a proposed draft.

        **Accept-path** (``request.accepted_spec`` is not None): save the accepted
        spec via the facade (which runs the diff guard + query gen), then run the
        agent with a short outcome note so it can acknowledge and invite further
        changes.  Returns ``saved=True``.

        **Normal turn**: if this is the first turn (no history), prepend the gym's
        current spec as readable context to the message so the agent knows the
        starting state without needing a tool call.  Returns ``saved=False``.
        """
        if self._agent is None:
            raise LookupError(
                "VideoAgentService: ANTHROPIC_API_KEY is not configured. "
                "Set it in .env to use the video-spec agent."
            )

        history = (
            ModelMessagesTypeAdapter.validate_python(request.history)
            if request.history
            else None
        )

        if request.accepted_spec is not None:
            return await self._handle_accept(
                gym_id, request.accepted_spec, history, request.history or []
            )

        return await self._handle_turn(gym_id, request.message, history)

    # ── private paths ────────────────────────────────────────────

    async def _handle_accept(
        self,
        gym_id: UUID,
        accepted_spec: VideoSpecDraft,
        history: object,
        raw_history: list,
    ) -> AgentTurnResponse:
        """Save the accepted spec and run the agent on a short outcome note.

        If the post-commit agent call fails the save already succeeded — return
        a best-effort acknowledgement with ``saved=True`` and a short fallback
        ``reply`` rather than propagating the error.

        The output is mapped the same way ``_handle_turn`` does so a post-save
        ``SpecProposal`` or ``AgentQuestion`` surfaces correctly (not flattened
        to reply-only).
        """
        view = await self._videos_service.save_accepted_spec(gym_id, accepted_spec)
        if view is not None:
            note = "[The proposed video spec has been saved.]"
        else:
            note = "[The proposed spec matched the current one; nothing changed.]"

        try:
            result = await self._agent.run(note, message_history=history)  # type: ignore[union-attr]
        except Exception:
            return AgentTurnResponse(
                saved=True,
                reply="The spec has been saved.",
                draft=None,
                history=raw_history,
                usage=None,
            )

        new_history = ModelMessagesTypeAdapter.dump_python(
            result.all_messages(), mode="json"
        )
        output = result.output
        # Map output the same way _handle_turn does so a post-save proposal or
        # question surfaces correctly (not flattened to a reply-only string).
        if isinstance(output, SpecProposal):
            reply, draft, question = output.message, output.draft, None
        elif isinstance(output, AgentQuestion):
            reply, draft, question = None, None, output
        else:
            reply = output if isinstance(output, str) else None
            draft, question = None, None
        return AgentTurnResponse(
            reply=reply,
            draft=draft,
            question=question,
            history=new_history,
            saved=True,
            usage=self._usage_dict(result.usage),
        )

    async def _handle_turn(
        self,
        gym_id: UUID,
        message: str,
        history: object,
    ) -> AgentTurnResponse:
        """Run a normal conversational turn, seeding state on the first turn."""
        if not history:
            current = await self._videos_service.load_latest_spec(gym_id)
            if current is not None:
                preamble = (
                    f"Current spec:\n"
                    f"- Disciplines: {', '.join(current.disciplines)}\n"
                    f"- Keep: {current.videos_desc}\n"
                    f"- Avoid: {current.avoid_desc}"
                )
            else:
                preamble = "This gym has no spec yet."
            message = f"{preamble}\n\n{message}" if message else preamble

        result = await self._agent.run(message, message_history=history)  # type: ignore[union-attr]
        new_history = ModelMessagesTypeAdapter.dump_python(
            result.all_messages(), mode="json"
        )
        output = result.output
        # A proposal always carries BOTH a chat message and the criteria draft;
        # a question or a plain reply set exactly one field.
        if isinstance(output, SpecProposal):
            reply, draft, question = output.message, output.draft, None
        elif isinstance(output, AgentQuestion):
            reply, draft, question = None, None, output
        else:  # plain text reply
            reply, draft, question = output, None, None
        return AgentTurnResponse(
            reply=reply,
            draft=draft,
            question=question,
            history=new_history,
            saved=False,
            usage=self._usage_dict(result.usage),
        )

    @staticmethod
    def _usage_dict(usage: object) -> dict[str, int]:
        return {
            key: getattr(usage, key)
            for key in ("requests", "input_tokens", "output_tokens", "total_tokens")
            if getattr(usage, key, None) is not None
        }
