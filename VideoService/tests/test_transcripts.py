"""The transcripts pass against a stubbed Apify fetch — no network.

Proves it maps results back to videos by id, stores the full transcript, leaves
missing ones None, and on a re-run only fetches the videos that still lack one.
The Apify item extraction is unit-tested via ``_extract_transcript``.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from schema import VideoOutput, VideosOutput
from scripts.transcripts import run as run_module
from scripts.transcripts.apify import TranscriptResults, _extract_transcript
from src.api.service.videos_service import VideosService


def _video(vid: str, *, relevance: int) -> VideoOutput:
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
    )


def _seed(tmp_path: Path) -> VideosService:
    service = VideosService(apps_root=tmp_path)
    output = VideosOutput(
        company_name="Demo Co",
        app_id="alpha",
        generated_at=datetime(2026, 5, 22, tzinfo=timezone.utc),
        quota_units_estimate=102,
        videos=[_video("aaa", relevance=0), _video("bbb", relevance=1)],
    )
    asyncio.run(service.save_output("alpha", output))
    return service


def _by_id(service: VideosService) -> dict[str, VideoOutput]:
    out = asyncio.run(service.load_output("alpha"))
    return {v.url.split("v=")[1]: v for v in out.videos}


def test_extract_transcript_shapes() -> None:
    assert _extract_transcript({"transcript": "  hi  "}) == "hi"
    assert _extract_transcript({"transcript": [{"text": "a"}, {"text": "b"}]}) == "a b"
    assert _extract_transcript({"errorCode": "TranscriptNotFound"}) is None
    assert _extract_transcript({"transcript": ""}) is None


def test_run_stores_found_and_records_error(tmp_path: Path, monkeypatch) -> None:
    service = _seed(tmp_path)
    monkeypatch.setattr(
        run_module, "transcript_settings", lambda: SimpleNamespace(apify_token="x")
    )
    # "aaa" gets a transcript; "bbb" comes back with a provider error.
    monkeypatch.setattr(
        run_module,
        "fetch_transcripts",
        lambda token, urls: TranscriptResults(
            transcripts={"aaa": "the transcript"},
            errors={"bbb": "AgeRestricted"},
        ),
    )
    run_module.run("alpha", apps_root=tmp_path)

    by_id = _by_id(service)
    assert by_id["aaa"].transcript == "the transcript"
    assert by_id["aaa"].transcript_error is None
    # Missing one keeps no transcript but records WHY.
    assert by_id["bbb"].transcript is None
    assert by_id["bbb"].transcript_error == "AgeRestricted"


def test_run_records_not_returned_when_absent(tmp_path: Path, monkeypatch) -> None:
    service = _seed(tmp_path)
    monkeypatch.setattr(
        run_module, "transcript_settings", lambda: SimpleNamespace(apify_token="x")
    )
    # Apify returned nothing at all for either url.
    monkeypatch.setattr(
        run_module, "fetch_transcripts", lambda token, urls: TranscriptResults()
    )
    run_module.run("alpha", apps_root=tmp_path)
    assert _by_id(service)["aaa"].transcript_error == "not_returned"


def test_transcript_cost_accumulates_in_manifest(tmp_path: Path, monkeypatch) -> None:
    from scripts.transcripts.apify import USD_PER_TRANSCRIPT

    service = _seed(tmp_path)  # 2 videos, neither has a transcript
    monkeypatch.setattr(
        run_module, "transcript_settings", lambda: SimpleNamespace(apify_token="x")
    )
    # First run: only "aaa" succeeds, but both urls were attempted (both billed).
    monkeypatch.setattr(
        run_module,
        "fetch_transcripts",
        lambda token, urls: TranscriptResults(transcripts={"aaa": "t"}),
    )
    run_module.run("alpha", apps_root=tmp_path)
    cost1 = asyncio.run(service.load_output("alpha")).transcript_cost_usd
    assert cost1 == 2 * USD_PER_TRANSCRIPT  # 2 urls attempted

    # Second run: only "bbb" is still pending (1 url), and it succeeds. Cost adds.
    monkeypatch.setattr(
        run_module,
        "fetch_transcripts",
        lambda token, urls: TranscriptResults(transcripts={"bbb": "t"}),
    )
    run_module.run("alpha", apps_root=tmp_path)
    cost2 = asyncio.run(service.load_output("alpha")).transcript_cost_usd
    assert cost2 == 3 * USD_PER_TRANSCRIPT  # 2 + 1, accumulated


def test_rerun_only_fetches_pending(tmp_path: Path, monkeypatch) -> None:
    service = _seed(tmp_path)
    monkeypatch.setattr(
        run_module, "transcript_settings", lambda: SimpleNamespace(apify_token="x")
    )
    calls: list[list[str]] = []

    def _fetch(token: str, urls: list[str]) -> TranscriptResults:
        calls.append(urls)
        return TranscriptResults(transcripts={u.split("v=")[1]: "t" for u in urls})

    monkeypatch.setattr(run_module, "fetch_transcripts", _fetch)

    run_module.run("alpha", apps_root=tmp_path)  # fetches both
    run_module.run("alpha", apps_root=tmp_path)  # both now have one -> no fetch

    assert len(calls[0]) == 2  # first run requested both
    # Second run found nothing pending, so fetch_transcripts was never called again.
    assert len(calls) == 1
