"""The pool tagging step: ``classify(video) -> VideoClassification``.

One structured LLM call per pooled video, schema in / verdict out, with
``complete_structured``'s validate-and-retry loop handling a malformed reply.
This pass is **gym-agnostic**: it judges only what the video IS — its genre
(``tag``) and the disciplines it is relevant to (``gym_type``) — from the video's
real content (title + description + runtime + transcript). It makes NO approval
decision; whether a gym shows the video is the separate per-gym scan
(``GymScanner``). The transcript is stored whole on ``VideoOutput`` but truncated
here to keep the prompt bounded; videos without one fall back to title +
description.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema.gym_type import GymType
from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

POOL_CLASSIFICATION_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "pool_classification.md"
)

# Model for the one pool-tagging call per video. A per-call constant, not config:
# the model is a property of this call. Override `classify(model=...)` in dev to
# compare models; production uses this default. Flash-Lite is fast, cheap,
# supports native structured output, and routes on the gemini provider key.
VIDEO_CLASSIFY_MODEL = "gemini/gemini-2.5-flash-lite"

# How much transcript to feed the tagger. The full transcript is stored on the
# video; the prompt only needs the start to judge genre/discipline, so we cap at
# ~3-4k tokens (~4 chars/token) of the head.
TRANSCRIPT_CHAR_BUDGET = 14000
# Shown in place of the transcript when a video has none so the prompt reads
# cleanly and the model leans on the title + description.
NO_TRANSCRIPT_PLACEHOLDER = (
    "(no transcript available — judge from the title and description)"
)


def gym_type_vocab() -> str:
    """The allowed ``gym_type`` discipline values as a bulleted list, for the
    prompt. Built from the enum so the prompt can never drift from the schema."""
    return "\n".join(f"  - {member.value}" for member in GymType)


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
    tagging pass's per-video log."""
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
    """Tags one pooled video (genre + disciplines) via a single LLM call."""

    def __init__(self, *, llm: LLMClient) -> None:
        self._llm = llm

    async def classify(
        self,
        video: VideoOutput,
        *,
        model: str = VIDEO_CLASSIFY_MODEL,
    ) -> VideoClassification:
        """Genre + disciplines for one video, judged from its own content."""
        template = POOL_CLASSIFICATION_PROMPT_PATH.read_text(encoding="utf-8")
        instruction = Template(template).safe_substitute(
            title=video.title,
            description=video.description,
            duration=format_duration(video.duration_seconds),
            transcript=truncate_transcript(video.transcript),
            gym_type_vocab=gym_type_vocab(),
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": instruction}],
            schema=VideoClassification,
            model=model,
        )
        logger.debug(
            "tagged %s -> tag=%s gym_type=%s",
            video.url,
            result.tag,
            [g.value for g in result.gym_type],
        )
        return result
