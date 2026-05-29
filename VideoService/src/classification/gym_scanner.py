"""The per-gym scan step: ``scan(video, gym) -> ScanVerdict``.

One structured LLM call per (gym, candidate video): given the gym's own
specifications and the video's content, decide whether the video belongs in THIS
gym's feed (``is_good``). Approval is a per-gym verdict — the same pool video can
be good for one gym and rejected by another — so this never mutates the pool; the
caller routes the verdict into the gym's ``good_video_ids`` / ``rejected_video_ids``.

Mirrors ``VideoClassifier``: schema in / verdict out via ``complete_structured``'s
validate-and-retry loop. Reuses the shared transcript/duration helpers.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema.gym import Gym
from schema.scan_verdict import ScanVerdict
from schema.video_output import VideoOutput
from src.classification.video_classifier import (
    VIDEO_CLASSIFY_MODEL,
    format_duration,
    truncate_transcript,
)
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

GYM_SCAN_PROMPT_PATH = Path(__file__).parent / "prompts" / "gym_scan.md"


class GymScanner:
    """Scans one candidate video against one gym's specifications via an LLM call."""

    def __init__(self, *, llm: LLMClient) -> None:
        self._llm = llm

    async def scan(
        self,
        video: VideoOutput,
        gym: Gym,
        *,
        model: str = VIDEO_CLASSIFY_MODEL,
    ) -> ScanVerdict:
        """Keep/drop verdict for one video against ``gym``'s specifications."""
        template = GYM_SCAN_PROMPT_PATH.read_text(encoding="utf-8")
        instruction = Template(template).safe_substitute(
            gym_type=", ".join(g.value for g in gym.gym_type),
            videos_desc=gym.videos.specification.videos_desc,
            avoid_desc=gym.videos.specification.avoid_desc,
            title=video.title,
            description=video.description,
            duration=format_duration(video.duration_seconds),
            transcript=truncate_transcript(video.transcript),
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": instruction}],
            schema=ScanVerdict,
            model=model,
        )
        logger.debug(
            "scanned %s for gym %s -> is_good=%s",
            video.url,
            gym.gym_id,
            result.is_good,
        )
        return result
