"""VideoClassifier (pool tagging) against a stubbed LLMClient — no network.

Proves the tagger feeds the video content + discipline vocabulary into the
prompt and returns the model's structured genre+disciplines verdict, plus the
transcript/duration helpers. The real LLM call (and its validate-and-retry) is
exercised by the ported client, not here. This pass is gym-agnostic — no brief.
"""

from __future__ import annotations

import asyncio

from schema.gym_type import GymType
from schema.video_classification import VideoClassification
from schema.video_output import VideoOutput
from schema.video_type import VideoType
from src.classification.video_classifier import (
    NO_TRANSCRIPT_PLACEHOLDER,
    TRANSCRIPT_CHAR_BUDGET,
    VideoClassifier,
    format_duration,
    gym_type_vocab,
    truncate_transcript,
)
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


def _verdict() -> VideoClassification:
    return VideoClassification(tag=VideoType.EDUCATIONAL, gym_type=[GymType.MUAY_THAI])


def _video(*, transcript: str | None = None) -> VideoOutput:
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
        transcript=transcript,
    )


def test_classify_returns_verdict_and_passes_context() -> None:
    verdict = _verdict()
    stub = _StubLLM(verdict)
    classifier = VideoClassifier(llm=stub)

    result = asyncio.run(classifier.classify(_video(), model="m"))
    assert result is verdict
    assert stub.last_model == "m"
    prompt = stub.last_messages[0]["content"]
    assert "Dominate the Muay Thai Clinch" in prompt  # video context
    assert "5m30s" in prompt  # formatted duration
    assert "muay_thai" in prompt  # the discipline vocabulary is injected


def test_classify_includes_transcript_when_present() -> None:
    stub = _StubLLM(_verdict())
    classifier = VideoClassifier(llm=stub)
    asyncio.run(
        classifier.classify(_video(transcript="grab the plum, drive the knee"), model="m")
    )
    assert "grab the plum, drive the knee" in stub.last_messages[0]["content"]


def test_classify_falls_back_to_placeholder_without_transcript() -> None:
    stub = _StubLLM(_verdict())
    classifier = VideoClassifier(llm=stub)
    asyncio.run(classifier.classify(_video(transcript=None), model="m"))
    assert NO_TRANSCRIPT_PLACEHOLDER in stub.last_messages[0]["content"]


def test_gym_type_vocab_lists_every_discipline() -> None:
    vocab = gym_type_vocab()
    # Every enum value appears, one per line, so the prompt can't drift.
    for member in GymType:
        assert member.value in vocab
    assert vocab.count("\n") + 1 == len(list(GymType))


def test_truncate_transcript() -> None:
    assert truncate_transcript(None) == NO_TRANSCRIPT_PLACEHOLDER
    assert truncate_transcript("   ") == NO_TRANSCRIPT_PLACEHOLDER
    assert truncate_transcript("short") == "short"
    clipped = truncate_transcript("x" * (TRANSCRIPT_CHAR_BUDGET + 1000))
    assert clipped.endswith("(transcript truncated)")
    assert len(clipped) <= TRANSCRIPT_CHAR_BUDGET + 40


def test_format_duration() -> None:
    assert format_duration(330) == "5m30s"
    assert format_duration(3600) == "1h"
    assert format_duration(3730) == "1h2m10s"
    assert format_duration(45) == "45s"
    assert format_duration(0) == "0s"
    assert format_duration(None) == "unknown"
