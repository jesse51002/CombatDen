"""Single-call YouTube search query generator (one structured LLM request).

Used by ``VideoSpecAuthoring`` after the diff guard confirms criteria have
changed. The genre-spread logic lives in exactly one place. Provider-swappable:
set ``video_llm_model`` in settings to any litellm provider string (e.g.
``openai/gpt-...`` / ``gemini/...``) whose key is configured.
"""

from __future__ import annotations

from string import Template

from src.shared.litellm_client import LiteLLMClient
from src.videos import PROMPTS_DIR
from src.videos.schema.video_spec_schema import (
    DEFAULT_QUERY_COUNT,
    QueriesResult,
)
from src.videos.schema.videos_gym_type import GymType

_PROMPT_PATH = PROMPTS_DIR / "video_query_generator.md"


class VideoQueryGenerator:
    """Generates a gym's YouTube search queries in one structured LLM call."""

    def __init__(
        self,
        *,
        litellm_client: LiteLLMClient,
        model: str,
    ) -> None:
        self._litellm_client = litellm_client
        self._model = model
        self._prompt_template = _PROMPT_PATH.read_text(encoding="utf-8")

    async def generate(
        self,
        *,
        disciplines: list[GymType],
        videos_desc: str,
        avoid_desc: str,
        count: int = DEFAULT_QUERY_COUNT,
    ) -> list[str]:
        """One LLM call: disciplines + keep/avoid criteria → search queries.

        All inputs must be provided by the caller — ``VideoSpecAuthoring`` is
        responsible for supplying them from the accepted ``VideoSpecDraft``.
        """
        prompt = Template(self._prompt_template).safe_substitute(
            disciplines=", ".join(d.value for d in disciplines),
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            count=count,
        )
        result = await self._litellm_client.complete_structured(
            prompt=prompt,
            schema=QueriesResult,
            model=self._model,
        )
        return result.queries
