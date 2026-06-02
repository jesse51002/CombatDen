"""The scraper's classify pass + the pool merge/dedup — no network.

Two things are proven here, both decoupled from the Apify fetch:

- ``classify_pool`` READS the whole pool from disk and tags only what's untagged:
  it gates on the transcript (no transcript -> never reaches the LLM) and is
  incremental (already-tagged videos are skipped, so re-runs don't re-spend).
- ``_merge_into_pool`` dedups a fresh scrape against the existing pool by video
  id, preserving existing tags and unioning the queries that surfaced a video.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from schema import VideoOutput
from schema.gym_type import GymType
from schema.video_classification import VideoClassification
from schema.video_type import VideoType
from scripts.scraper import run as run_module
from src.api.service.videos_service import VideosService

# The scraper isn't migrated to the SQL writer yet (deferred A3): its classify
# pass + pool merge still call the removed YAML VideosService write methods
# (save_video / load_pool / save_pool). Skipped until the scrape/scan -> SQL
# rewrite re-enables (and updates) these tests.
pytestmark = pytest.mark.skip(
    reason="scraper not yet migrated to the SQL writer (A3); "
    "re-enabled with the scrape/scan -> SQL rewrite"
)


def _video(
    vid: str,
    *,
    relevance: int = 0,
    transcript: str | None = None,
    tag: VideoType | None = None,
    gym_type: list[GymType] | None = None,
    source_queries: list[str] | None = None,
) -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="d",
        thumbnail_url="t",
        channel_name="Some Channel",
        channel_url="cu",
        channel_avatar_url="a",
        source_queries=source_queries or ["q"],
        relevance_index=relevance,
        transcript=transcript,
        tag=tag,
        gym_type=gym_type or [],
    )


class _DummyLLM:
    cost = 0.0123


def _stub(monkeypatch, tagged_ids: list[str]) -> None:
    """Stub the LLM + classifier so no network is touched; record tagged ids."""

    class _StubClassifier:
        def __init__(self, *, llm) -> None:  # noqa: ANN001
            self._llm = llm

        async def classify(self, video, *, model):  # noqa: ANN001, ARG002
            tagged_ids.append(video.url.split("v=")[1])
            return VideoClassification(
                tag=VideoType.EDUCATIONAL, gym_type=[GymType.MUAY_THAI]
            )

    monkeypatch.setattr(run_module, "LiteLLMClient", _DummyLLM)
    monkeypatch.setattr(run_module, "VideoClassifier", _StubClassifier)


def _seed(tmp_path: Path, *videos: VideoOutput) -> VideosService:
    service = VideosService(root=tmp_path)
    for v in videos:
        asyncio.run(service.save_video(v))
    return service


def _pool_by_id(service: VideosService) -> dict[str, VideoOutput]:
    return {v.url.split("v=")[1]: v for v in asyncio.run(service.load_pool())}


# --- classify reads the pool + gates on transcript --------------------------


def test_classify_reads_pool_and_skips_no_transcript(tmp_path: Path, monkeypatch) -> None:
    tagged_ids: list[str] = []
    _stub(monkeypatch, tagged_ids)
    service = _seed(
        tmp_path,
        _video("hastx", relevance=0, transcript="a real transcript"),
        _video("notx", relevance=1, transcript=None),
    )
    # No videos are passed in — classify reads them all from disk itself.
    asyncio.run(run_module.classify_pool(service, model="m"))

    assert tagged_ids == ["hastx"]  # only the transcript-backed video reached the LLM
    by_id = _pool_by_id(service)
    assert by_id["hastx"].tag == VideoType.EDUCATIONAL
    assert [g.value for g in by_id["hastx"].gym_type] == ["muay_thai"]
    assert by_id["notx"].tag is None  # left untagged, never tagged
    assert by_id["notx"].gym_type == []


def test_classify_is_incremental_skips_already_tagged(tmp_path: Path, monkeypatch) -> None:
    tagged_ids: list[str] = []
    _stub(monkeypatch, tagged_ids)
    service = _seed(
        tmp_path,
        # Already classified on a prior run — must be skipped (no re-spend).
        _video("old", transcript="tx", tag=VideoType.CLIPS, gym_type=[GymType.BOXING]),
        # Freshly scraped, untagged — the only one that should be tagged now.
        _video("new", relevance=1, transcript="tx"),
    )
    asyncio.run(run_module.classify_pool(service, model="m"))

    assert tagged_ids == ["new"]  # the already-tagged "old" was skipped
    by_id = _pool_by_id(service)
    assert by_id["old"].tag == VideoType.CLIPS  # untouched
    assert by_id["new"].tag == VideoType.EDUCATIONAL


def test_classify_logs_tag_cost(tmp_path: Path, monkeypatch) -> None:
    _stub(monkeypatch, [])
    service = _seed(tmp_path, _video("hastx", transcript="tx"))
    asyncio.run(run_module.classify_pool(service, model="m"))

    log = asyncio.run(service.load_cost_log())
    tag_entries = [e for e in log if e.execution_type.value == "tag"]
    assert len(tag_entries) == 1
    assert tag_entries[0].breakdown["llm_usd"] == 0.0123  # from the stub LLM


def test_classify_no_work_writes_no_cost(tmp_path: Path, monkeypatch) -> None:
    _stub(monkeypatch, [])
    service = _seed(tmp_path, _video("notx", transcript=None))  # nothing taggable
    asyncio.run(run_module.classify_pool(service, model="m"))
    assert asyncio.run(service.load_cost_log()) == []  # no empty TAG entry


# --- merge / dedup against the existing pool --------------------------------


def test_merge_dedups_and_preserves_tags() -> None:
    existing = [
        # Already in the pool and tagged — must be preserved, not retagged.
        _video(
            "A",
            transcript="tx",
            tag=VideoType.CLIPS,
            gym_type=[GymType.BOXING],
            source_queries=["q1"],
            relevance=2,
        ),
        _video("B", source_queries=["q1"]),
    ]
    fresh = [
        # Same id as A, surfaced by a new query at a better rank.
        _video("A", source_queries=["q2"], relevance=0),
        # Genuinely new.
        _video("C", source_queries=["q2"]),
    ]
    merged, to_persist, new_count = run_module._merge_into_pool(existing, fresh)

    by_id = {v.url.split("v=")[1]: v for v in merged}
    assert set(by_id) == {"A", "B", "C"}  # deduped: A appears once
    assert new_count == 1  # only C is new
    # A kept its tag and unioned its queries + best relevance.
    assert by_id["A"].tag == VideoType.CLIPS
    assert by_id["A"].source_queries == ["q1", "q2"]
    assert by_id["A"].relevance_index == 0
    # to_persist is just the changed A + the new C (B was untouched).
    persisted = {v.url.split("v=")[1] for v in to_persist}
    assert persisted == {"A", "C"}


def test_merge_adds_transcript_to_existing_without_one() -> None:
    existing = [_video("A", transcript=None, source_queries=["q1"])]
    fresh = [_video("A", transcript="now has captions", source_queries=["q1"])]
    merged, to_persist, _ = run_module._merge_into_pool(existing, fresh)
    assert merged[0].transcript == "now has captions"
    assert len(to_persist) == 1  # the gained transcript is a change worth writing
