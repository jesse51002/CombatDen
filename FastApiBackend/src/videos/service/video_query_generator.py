"""Two-call YouTube search query generator (landscape research → query gen).

Used by ``VideoSpecAuthoring`` after the diff guard confirms criteria have
changed. Call 1 researches the niche's content landscape (channels / creators /
series); call 2 turns criteria + that landscape into concrete search queries.
The genre-spread logic lives in exactly one place. Provider-swappable: set
``video_llm_model`` in settings to any litellm provider string (e.g.
``openai/gpt-...`` / ``gemini/...``) whose key is configured — both calls use it.
"""

from __future__ import annotations

from string import Template

from src.shared.litellm_client import LiteLLMClient
from src.videos import PROMPTS_DIR
from src.videos.schema.video_spec_schema import (
    LandscapeResult,
    QueriesResult,
)
from src.videos.schema.videos_gym_type import GymType

_LANDSCAPE_PROMPT_PATH = PROMPTS_DIR / "video_landscape.md"
_QUERY_PROMPT_PATH = PROMPTS_DIR / "video_query_generator.md"


class VideoQueryGenerator:
    """Generates a gym's YouTube search queries via two structured LLM calls."""

    def __init__(
        self,
        *,
        litellm_client: LiteLLMClient,
        model: str,
    ) -> None:
        self._litellm_client = litellm_client
        self._model = model
        self._landscape_template = _LANDSCAPE_PROMPT_PATH.read_text(
            encoding="utf-8"
        )
        self._query_template = _QUERY_PROMPT_PATH.read_text(encoding="utf-8")

    async def generate(
        self,
        *,
        disciplines: list[GymType],
        videos_desc: str,
        avoid_desc: str,
        count: int,
    ) -> list[str]:
        """Two LLM calls: research the content landscape, then generate queries.

        Step 1 (landscape research): from the disciplines + keep/avoid criteria
        the LLM brainstorms the niche's well-known content — popular channels,
        recognizable creators / athletes, and notable series / events — as a
        :class:`LandscapeResult`. Hallucination is tolerated by design (a wrong
        name just searches poorly), so nothing is validated.

        Step 2 (query generation): the landscape is rendered into the query
        prompt so roughly one third of the queries can target those names
        ("<channel> highlights", "<athlete> interview"), while the whole set
        keeps the 5-cluster genre spread (~half teach). Both calls go through the
        injected :class:`LiteLLMClient` with ``settings.video_llm_model``.

        All inputs must be provided by the caller — ``VideoSpecAuthoring`` is
        responsible for supplying them from the accepted ``VideoSpecDraft``.
        """
        disciplines_text = ", ".join(d.value for d in disciplines)

        landscape_prompt = Template(self._landscape_template).safe_substitute(
            disciplines=disciplines_text,
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
        )
        landscape = await self._litellm_client.complete_structured(
            prompt=landscape_prompt,
            schema=LandscapeResult,
            model=self._model,
        )

        query_prompt = Template(self._query_template).safe_substitute(
            disciplines=disciplines_text,
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            landscape=self._render_landscape(landscape),
            count=count,
        )
        result = await self._litellm_client.complete_structured(
            prompt=query_prompt,
            schema=QueriesResult,
            model=self._model,
        )
        return result.queries

    @staticmethod
    def _render_landscape(landscape: LandscapeResult) -> str:
        """Render a :class:`LandscapeResult` into readable bullet lists for the
        ``$landscape`` slot of the query-generation prompt.

        Empty sections render an explicit ``(none)`` line so the downstream
        prompt still reads cleanly regardless of what the research call returned.
        """
        sections = (
            ("Channels", landscape.channels),
            ("Creators / athletes", landscape.creators),
            ("Series / events", landscape.series_events),
        )
        blocks: list[str] = []
        for label, names in sections:
            lines = (
                "\n".join(f"- {name}" for name in names) if names else "- (none)"
            )
            blocks.append(f"**{label}:**\n{lines}")
        return "\n\n".join(blocks)
