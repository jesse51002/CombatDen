"""Audit helpers: video-id parsing, kept/removed partition, and the in-place
rewrite + removed-sidecar that `remove_videos` performs."""

from __future__ import annotations

from pathlib import Path

import yaml

from schema import VideosOutput
from scripts.youtube_batch.audit import (
    partition_videos,
    remove_videos,
    video_id_from_url,
)

_OUTPUT_YAML = """\
company_name: Demo Gym
app_id: demo
generated_at: 2026-05-22T00:00:00Z
quota_units_estimate: 102
videos:
  - url: https://www.youtube.com/watch?v=keepme
    title: How to Throw a Teep Kick
    description: d
    thumbnail_url: t
    channel_name: Muay Thai Guy
    channel_url: cu
    channel_avatar_url: a
    view_count: 1000
    like_count: 50
    tag: educational
    source_queries: [teep]
    relevance_index: 0
  - url: https://www.youtube.com/watch?v=dropme
    title: Why Muay Thai Doesn't Work
    description: d
    thumbnail_url: t
    channel_name: Contrarian Channel
    channel_url: cu
    channel_avatar_url: a
    view_count: 2000
    like_count: 5
    tag: analysis
    source_queries: [does muay thai work]
    relevance_index: 1
"""


def _seed(tmp_path: Path) -> Path:
    app_dir = tmp_path / "demo"
    app_dir.mkdir()
    (app_dir / "videos_output.yaml").write_text(_OUTPUT_YAML)
    return tmp_path


def test_video_id_from_url() -> None:
    assert video_id_from_url("https://www.youtube.com/watch?v=abc123") == "abc123"
    assert video_id_from_url("https://youtube.com/watch?v=x&t=10s") == "x"
    assert video_id_from_url("not a url") == ""


def test_partition_preserves_order() -> None:
    output = VideosOutput.model_validate(yaml.safe_load(_OUTPUT_YAML))
    kept, removed = partition_videos(output.videos, {"dropme"})
    assert [video_id_from_url(v.url) for v in kept] == ["keepme"]
    assert [video_id_from_url(v.url) for v in removed] == ["dropme"]


def test_remove_rewrites_output_and_logs_sidecar(tmp_path: Path) -> None:
    apps_root = _seed(tmp_path)
    remove_videos("demo", apps_root, ["dropme"], reason="negative about muay thai")

    # Survivors rewritten in place, still schema-valid.
    out = VideosOutput.model_validate(
        yaml.safe_load((apps_root / "demo" / "videos_output.yaml").read_text())
    )
    assert [video_id_from_url(v.url) for v in out.videos] == ["keepme"]

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
