"""Single-call YouTube search query generator (one structured LLM request).

Used by BOTH the standalone ``generate-queries`` endpoint and the conversational
agent's ``generate_queries`` tool, so the genre-spread logic lives in exactly one
place. Provider-swappable: the model is whatever string it was built with (e.g.
``anthropic:claude-sonnet-4-6``); the provider key is published to the env by
``configure_provider_keys`` at build time.
"""

from __future__ import annotations

from string import Template

from pydantic_ai import Agent

from src.video_config import PROMPTS_DIR
from src.video_config.schema.video_config_schema import (
    DEFAULT_QUERY_COUNT,
    QueriesResult,
)
from src.videos.schema.videos_gym_type import GymType

_PROMPT_PATH = PROMPTS_DIR / "video_config_query_generator.md"


class VideoConfigQueryGenerator:
    """Generates a gym's YouTube search queries in one structured LLM call."""

    def __init__(self, *, model: str, retries: int) -> None:
        self._prompt_template = _PROMPT_PATH.read_text(encoding="utf-8")
        self._agent: Agent[None, QueriesResult] = Agent(
            model,
            output_type=QueriesResult,
            retries=retries,
            # Resolve the model (and its provider key) at call time, not now, so
            # the backend boots even before ANTHROPIC_API_KEY is configured.
            defer_model_check=True,
        )

    async def generate(
        self,
        *,
        disciplines: list[GymType],
        videos_desc: str,
        avoid_desc: str,
        count: int = DEFAULT_QUERY_COUNT,
    ) -> list[str]:
        """One LLM call: disciplines + keep/avoid criteria -> search queries."""
        prompt = Template(self._prompt_template).safe_substitute(
            disciplines=", ".join(d.value for d in disciplines),
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            count=count,
        )
        result = await self._agent.run(prompt)
        return result.output.queries
