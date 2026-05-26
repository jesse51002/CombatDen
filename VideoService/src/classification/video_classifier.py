"""The classification step: ``classify(video, brief) -> VideoClassification``.

Mirrors ``CustomizationService``'s ``ComplexityClassifier`` — one structured LLM
call per video, schema in / verdict out, with ``complete_structured``'s
validate-and-retry loop handling a malformed reply. The genre and keep/drop
verdict come from the video's real content (title + description + runtime +
transcript) judged against the company brief, not from the search that surfaced
it. The transcript is stored whole on ``VideoOutput`` but truncated here to keep
the prompt bounded; videos without one fall back to title + description.
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

# How much transcript to feed the classifier. The full transcript is stored on
# the video; the prompt only needs the start to judge genre/relevance, so we cap
# at ~3-4k tokens (~4 chars/token) of the head. Keeps a 3-hour podcast from
# blowing up cost/context while every normal video passes through whole.
TRANSCRIPT_CHAR_BUDGET = 14000
# Shown in place of the transcript when a video has none (no captions / fetch
# failed / transcripts pass not run) so the prompt reads cleanly and the model
# knows to lean on the title + description.
NO_TRANSCRIPT_PLACEHOLDER = "(no transcript available — judge from the title and description)"


def truncate_transcript(text: str | None) -> str:
    """The transcript clipped to ``TRANSCRIPT_CHAR_BUDGET`` head characters, or
    the placeholder when there is none. A clipped transcript gets a trailing
    marker so the model knows it was cut."""
    if not text or not text.strip():
        return NO_TRANSCRIPT_PLACEHOLDER
    text = text.strip()
    if len(text) <= TRANSCRIPT_CHAR_BUDGET:
        return text
    return text[:TRANSCRIPT_CHAR_BUDGET].rstrip() + "\n…(transcript truncated)"


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
            queries="\n".join(f"- {s.query}" for s in brief.searches),
            title=video.title,
            description=video.description,
            duration=format_duration(video.duration_seconds),
            transcript=truncate_transcript(video.transcript),
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
