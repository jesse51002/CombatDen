"""The conversational video-config agent + its tools (Pydantic AI).

The agent interviews a gym owner and either replies with text (its next question)
or produces a finished :class:`VideoConfigDraft` as structured output. Its two
tools are the single-call query generator and a reader for the gym's current
config (so it can *refine*, not only create). Per-run dependencies (the gym id,
the query generator, and a config-loader callable) are passed via
:class:`VideoConfigDeps` and reached through ``RunContext``.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from uuid import UUID

from pydantic_ai import Agent, RunContext

from src.video_config import PROMPTS_DIR
from src.video_config.schema.video_config_schema import (
    DEFAULT_QUERY_COUNT,
    VideoConfigDraft,
    VideoConfigView,
)
from src.video_config.service.video_config_query_generator import (
    VideoConfigQueryGenerator,
)
from src.videos.schema.videos_gym_type import GymType

_SYSTEM_PROMPT_PATH = PROMPTS_DIR / "video_config_agent_system.md"

# The agent outputs free text (its next message) OR a finished draft.
VideoConfigAgentOutput = str | VideoConfigDraft


@dataclass
class VideoConfigDeps:
    """Per-run dependencies the agent's tools need."""

    gym_id: UUID
    query_generator: VideoConfigQueryGenerator
    load_current_config: Callable[[UUID], Awaitable[VideoConfigView | None]]


def build_video_config_agent(
    *, model: str, retries: int
) -> Agent[VideoConfigDeps, VideoConfigAgentOutput]:
    """Build the conversational agent once (reused across requests; state is
    carried per-run via ``message_history`` + ``deps``)."""
    system_prompt = _SYSTEM_PROMPT_PATH.read_text(encoding="utf-8")
    agent: Agent[VideoConfigDeps, VideoConfigAgentOutput] = Agent(
        model,
        deps_type=VideoConfigDeps,
        output_type=[str, VideoConfigDraft],
        instructions=system_prompt,
        retries=retries,
        # Resolve the model (and its provider key) at call time, not now, so the
        # backend boots even before ANTHROPIC_API_KEY is configured.
        defer_model_check=True,
    )

    @agent.tool
    async def generate_queries(
        ctx: RunContext[VideoConfigDeps],
        disciplines: list[GymType],
        videos_desc: str,
        avoid_desc: str,
        count: int = DEFAULT_QUERY_COUNT,
    ) -> list[str]:
        """Generate YouTube search queries spread across the video genres for the
        given disciplines + keep/avoid criteria. Use this to draft the feed's
        queries instead of writing them yourself."""
        return await ctx.deps.query_generator.generate(
            disciplines=disciplines,
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            count=count,
        )

    @agent.tool
    async def read_current_config(
        ctx: RunContext[VideoConfigDeps],
    ) -> VideoConfigView | None:
        """Read the gym's CURRENT saved video config (its latest version) so you
        can refine it. Returns null if the gym has no config yet."""
        return await ctx.deps.load_current_config(ctx.deps.gym_id)

    return agent
