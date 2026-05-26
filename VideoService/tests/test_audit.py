"""Audit helpers: video-id parsing, kept/removed partition, and the per-video
file deletion + removed-sidecar that `remove_videos` performs."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import yaml

from schema import VideoOutput, VideosOutput
from src.api.service.videos_service import VideosService
from scripts.youtube_batch.audit import (
    partition_videos,
    remove_videos,
    video_id_from_url,
)


def _video(vid: str, title: str, *, relevance: int) -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=title,
        description="d",
        thumbnail_url="t",
        channel_name="Some Channel",
        channel_url="cu",
        channel_avatar_url="a",
        view_count=1000,
        like_count=50,
        source_queries=["q"],
        relevance_index=relevance,
    )


_OUTPUT = VideosOutput(
    company_name="Demo Gym",
    app_id="demo",
    generated_at=datetime(2026, 5, 22, tzinfo=timezone.utc),
    quota_units_estimate=102,
    videos=[
        _video("keepme", "How to Throw a Teep Kick", relevance=0),
        _video("dropme", "Why Muay Thai Doesn't Work", relevance=1),
    ],
)


def _seed(tmp_path: Path) -> Path:
    asyncio.run(VideosService(apps_root=tmp_path).save_output("demo", _OUTPUT))
    return tmp_path


def _video_ids(apps_root: Path) -> list[str]:
    return asyncio.run(VideosService(apps_root=apps_root).list_video_ids("demo"))


def test_video_id_from_url() -> None:
    assert video_id_from_url("https://www.youtube.com/watch?v=abc123") == "abc123"
    assert video_id_from_url("https://youtube.com/watch?v=x&t=10s") == "x"
    assert video_id_from_url("not a url") == ""


def test_partition_preserves_order() -> None:
    kept, removed = partition_videos(_OUTPUT.videos, {"dropme"})
    assert [video_id_from_url(v.url) for v in kept] == ["keepme"]
    assert [video_id_from_url(v.url) for v in removed] == ["dropme"]


def test_remove_deletes_file_and_logs_sidecar(tmp_path: Path) -> None:
    apps_root = _seed(tmp_path)
    remove_videos("demo", apps_root, ["dropme"], reason="negative about muay thai")

    # The dropped video's file is gone; the survivor remains.
    assert _video_ids(apps_root) == ["keepme"]

    # Removed video logged with its reason.
    removed_doc = yaml.safe_load(
        (apps_root / "demo" / "videos_output.removed.yaml").read_text()
    )
    assert len(removed_doc["removed"]) == 1
    rec = removed_doc["removed"][0]
    assert rec["title"] == "Why Muay Thai Doesn't Work"
    assert rec["removed_reason"] == "negative about muay thai"
    assert "removed_at" in rec


def test_remove_appends_across_runs(tmp_path: Path) -> None:
    apps_root = _seed(tmp_path)
    remove_videos("demo", apps_root, ["dropme"], reason="first pass")
    # A second pass removing the survivor should append, not overwrite the log.
    remove_videos("demo", apps_root, ["keepme"], reason="second pass")
    removed_doc = yaml.safe_load(
        (apps_root / "demo" / "videos_output.removed.yaml").read_text()
    )
    assert len(removed_doc["removed"]) == 2
    assert {r["removed_reason"] for r in removed_doc["removed"]} == {
        "first pass", "second pass",
    }
