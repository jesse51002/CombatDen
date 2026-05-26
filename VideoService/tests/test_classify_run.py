"""The classify pass's transcript gate: a video without a transcript never
reaches the LLM and is flagged is_good=False; only transcript-backed videos are
classified. Stubs the classifier so no network / API key is needed."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

from schema import VerdictReason, VideoOutput, VideosOutput
from schema.video_classification import VideoClassification
from schema.video_type import VideoType
from scripts.classify import run as run_module
from src.api.service.videos_service import VideosService

_CONFIG = """\
company_name: Demo Co
type: Demo niche
videos_desc: Videos worth surfacing.
avoid_desc: Content to avoid.
searches:
""" + "".join(f"  - query: demo search {i}\n" for i in range(10))


def _video(vid: str, *, relevance: int, transcript: str | None) -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="d",
        thumbnail_url="t",
        channel_name="Some Channel",
        channel_url="cu",
        channel_avatar_url="a",
        source_queries=["q"],
        relevance_index=relevance,
        transcript=transcript,
    )


class _DummyLLM:
    cost = 0.0123


def _seed(tmp_path: Path) -> VideosService:
    (tmp_path / "alpha").mkdir(parents=True)
    (tmp_path / "alpha" / "videos_config.yaml").write_text(_CONFIG)
    service = VideosService(apps_root=tmp_path)
    output = VideosOutput(
        company_name="Demo Co",
        app_id="alpha",
        generated_at=datetime(2026, 5, 22, tzinfo=timezone.utc),
        quota_units_estimate=102,
        videos=[
            _video("hastx", relevance=0, transcript="a real transcript"),
            _video("notx", relevance=1, transcript=None),
        ],
    )
    asyncio.run(service.save_output("alpha", output))
    return service


def _run_with_stub(tmp_path: Path, monkeypatch, *, is_good: bool, classified_ids: list[str]):
    class _StubClassifier:
        def __init__(self, *, llm) -> None:  # noqa: ANN001
            self._llm = llm

        async def classify(self, video, brief, *, model):  # noqa: ANN001, ARG002
            classified_ids.append(video.url.split("v=")[1])
            return VideoClassification(is_good=is_good, tag=VideoType.EDUCATIONAL)

    monkeypatch.setattr(run_module, "LiteLLMClient", _DummyLLM)
    monkeypatch.setattr(run_module, "VideoClassifier", _StubClassifier)
    service = _seed(tmp_path)
    asyncio.run(run_module.run("alpha", apps_root=tmp_path, model="m"))
    return {v.url.split("v=")[1]: v for v in asyncio.run(service.load_output("alpha")).videos}


def test_transcript_gate_skips_llm_and_flags_not_good(tmp_path: Path, monkeypatch) -> None:
    classified_ids: list[str] = []
    by_id = _run_with_stub(tmp_path, monkeypatch, is_good=True, classified_ids=classified_ids)

    # Only the transcript-backed video reached the classifier (the LLM gate).
    assert classified_ids == ["hastx"]
    # Classified-good video keeps its verdict; no reason.
    assert by_id["hastx"].is_good is True
    assert by_id["hastx"].tag == VideoType.EDUCATIONAL
    assert by_id["hastx"].reason is None
    # Transcript-less video is flagged not-good (reason NO_TRANSCRIPT), never classified.
    assert by_id["notx"].is_good is False
    assert by_id["notx"].tag is None
    assert by_id["notx"].reason == VerdictReason.NO_TRANSCRIPT


def test_llm_rejection_sets_reason(tmp_path: Path, monkeypatch) -> None:
    classified_ids: list[str] = []
    by_id = _run_with_stub(tmp_path, monkeypatch, is_good=False, classified_ids=classified_ids)
    # The transcript-backed video was judged bad by the LLM.
    assert by_id["hastx"].is_good is False
    assert by_id["hastx"].reason == VerdictReason.LLM_CLASSIFIED_BAD
    # The transcript-less one is still NO_TRANSCRIPT (never reached the LLM).
    assert by_id["notx"].reason == VerdictReason.NO_TRANSCRIPT


def test_classification_cost_written_to_manifest(tmp_path: Path, monkeypatch) -> None:
    _run_with_stub(tmp_path, monkeypatch, is_good=True, classified_ids=[])
    out = asyncio.run(VideosService(apps_root=tmp_path).load_output("alpha"))
    assert out.classification_cost_usd == 0.0123  # from the stub LLM's cost
