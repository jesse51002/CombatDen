"""The classification step: ``classify(video, brief) -> VideoClassification``.

Mirrors ``CustomizationService``'s ``ComplexityClassifier`` — one structured LLM
call per video, schema in / verdict out, with ``complete_structured``'s
validate-and-retry loop handling a malformed reply. The genre and keep/drop
verdict come from the video's real content (title + description + runtime)
judged against the company brief, not from the search that surfaced it.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from schema.videos_config import VideosConfig
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

VIDEO_CLASSIFICATION_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "video_classification.md"
)

# Model for the one classification call per video. A per-call constant, not
# config: the model is a property of this call. Override `classify(model=...)`
# in dev to compare models; production uses this default. Flash-Lite is fast,
# cheap, supports native structured output, and routes on the gemini provider
# key (see src/core/config.py + provider_keys).
VIDEO_CLASSIFY_MODEL = "gemini/gemini-2.5-flash-lite"


def format_duration(seconds: int | None) -> str:
    """Human runtime: ``5m30s`` / ``1h2m`` / ``45s``. ``unknown`` when the API
    reported no duration (e.g. a live broadcast). Shared by the prompt and the
    classify pass's per-video log."""
    if seconds is None:
        return "unknown"
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if secs or not parts:
        parts.append(f"{secs}s")
    return "".join(parts)


class VideoClassifier:
    """Classifies one video against a company brief via a single LLM call."""

    def __init__(self, *, llm: LLMClient) -> None:
        self._llm = llm

    async def classify(
        self,
        video: VideoOutput,
        brief: VideosConfig,
        *,
        model: str = VIDEO_CLASSIFY_MODEL,
    ) -> VideoClassification:
        """Genre + keep/drop verdict for one video, judged against ``brief``."""
        template = VIDEO_CLASSIFICATION_PROMPT_PATH.read_text(encoding="utf-8")
        instruction = Template(template).safe_substitute(
            company_name=brief.company_name,
            type=brief.type,
            videos_desc=brief.videos_desc,
            avoid_desc=brief.avoid_desc,
            title=video.title,
            description=video.description,
            duration=format_duration(video.duration_seconds),
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": instruction}],
            schema=VideoClassification,
            model=model,
        )
        logger.debug(
            "classified %s -> tag=%s is_good=%s",
            video.url,
            result.tag,
            result.is_good,
        )
        return result
