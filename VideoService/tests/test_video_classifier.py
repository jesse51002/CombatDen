"""VideoClassifier against a stubbed LLMClient — no network.

Proves the classifier feeds the brief + video into the prompt and returns the
model's structured verdict, plus the duration formatting helper. The real LLM
call (and its validate-and-retry) is exercised by the ported client, not here.
"""

from __future__ import annotations

import asyncio

from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from schema.video_type import VideoType
from schema.videos_config import VideosConfig
from src.classification.video_classifier import VideoClassifier, format_duration
from src.shared.interfaces.llm_client import LLMClient, ModelT


class _StubLLM(LLMClient):
    """Records the last structured call and returns a canned verdict."""

    def __init__(self, verdict: VideoClassification) -> None:
        self._verdict = verdict
        self.last_messages: list[dict] | None = None
        self.last_model: str | None = None

    async def complete(self, messages, *, model, tools=None) -> dict:  # noqa: ARG002
        raise NotImplementedError

    async def complete_structured(
        self, messages, *, schema: type[ModelT], model: str
    ) -> ModelT:
        self.last_messages = messages
        self.last_model = model
        assert schema is VideoClassification
        return self._verdict  # type: ignore[return-value]


def _brief() -> VideosConfig:
    return VideosConfig(
        company_name="Bangkok Muay Thai Academy",
        type="Muay Thai gym",
        videos_desc="Clinch and technique tutorials, elite stadium footage.",
        avoid_desc="Cardio-kickboxing mislabeled as Muay Thai.",
        searches=[{"query": "muay thai clinch tutorial"}],
    )


def _video() -> VideoOutput:
    return VideoOutput(
        url="https://www.youtube.com/watch?v=abc",
        title="Dominate the Muay Thai Clinch",
        description="A step-by-step clinch breakdown.",
        thumbnail_url="https://i.ytimg.com/vi/abc/hqdefault.jpg",
        channel_name="fightTIPS",
        channel_url="https://www.youtube.com/channel/c1",
        channel_avatar_url="https://yt3.ggpht.com/pfp",
        duration_seconds=330,
        source_queries=["muay thai clinch tutorial"],
        relevance_index=0,
    )


def test_classify_returns_verdict_and_passes_context() -> None:
    verdict = VideoClassification(is_good=True, tag=VideoType.EDUCATIONAL)
    stub = _StubLLM(verdict)
    classifier = VideoClassifier(llm=stub)

    result = asyncio.run(classifier.classify(_video(), _brief(), model="m"))
    assert result is verdict
    assert stub.last_model == "m"
    # Brief + video context made it into the single user message.
    prompt = stub.last_messages[0]["content"]
    assert "Bangkok Muay Thai Academy" in prompt
    assert "Dominate the Muay Thai Clinch" in prompt
    assert "5m30s" in prompt  # formatted duration


def test_format_duration() -> None:
    assert format_duration(330) == "5m30s"
    assert format_duration(3600) == "1h"
    assert format_duration(3730) == "1h2m10s"
    assert format_duration(45) == "45s"
    assert format_duration(0) == "0s"
    assert format_duration(None) == "unknown"
