"""Round-trip every example videos_config.yaml against the model, plus the
search-count bounds the contract promises. Searches are query-only — genre is
assigned per-video by the classification pass, not in the brief."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from pydantic import ValidationError

from schema import VideosConfig, VideoType

APPS_ROOT = Path(__file__).resolve().parent.parent / "apps"


# smoketest is a deliberately-minimal single-search fixture for the batch
# script, not a curated company brief, so it's exempt from the quality gates
# below (it's still schema-validated when `make smoke` loads it).
_QUALITY_EXEMPT = {"smoketest"}


def _example_paths() -> list[Path]:
    return sorted(
        p
        for p in APPS_ROOT.glob("*/videos_config.yaml")
        if p.parent.name not in _QUALITY_EXEMPT
    )


def _base_doc() -> dict:
    """A minimal valid document (10 searches) tests can mutate."""
    return {
        "company_name": "Test Co",
        "type": "Test niche",
        "videos_desc": "Videos worth surfacing.",
        "avoid_desc": "Content to avoid.",
        "searches": [{"query": f"test search {i}"} for i in range(10)],
    }


def test_examples_exist() -> None:
    assert _example_paths(), "no apps/*/videos_config.yaml examples found"


@pytest.mark.parametrize("path", _example_paths(), ids=lambda p: p.parent.name)
def test_example_round_trips(path: Path) -> None:
    config = VideosConfig.model_validate(yaml.safe_load(path.read_text()))

    # At least one search, each a non-empty query (no tags — query-only).
    assert len(config.searches) >= 1
    for search in config.searches:
        assert search.query.strip()
        assert not hasattr(search, "tags")


def test_empty_searches_rejected() -> None:
    doc = _base_doc()
    doc["searches"] = []
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_search_tags_rejected() -> None:
    # A stray `tags` on a search now fails (searches are query-only, extra=forbid).
    doc = _base_doc()
    doc["searches"][0]["tags"] = ["educational"]
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_extra_key_rejected() -> None:
    doc = _base_doc()
    doc["unexpected"] = "nope"
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_video_type_serializes_to_lowercase() -> None:
    assert VideoType.PROFESSIONAL.value == "professional"
    assert VideoType.Memes.value == "memes"


def test_priority_channels_defaults_to_empty() -> None:
    config = VideosConfig.model_validate(_base_doc())
    assert config.priority_channels == []


def test_priority_channels_captured_when_present() -> None:
    doc = _base_doc()
    doc["priority_channels"] = ["@MyGym", "ONE Championship"]
    config = VideosConfig.model_validate(doc)
    assert config.priority_channels == ["@MyGym", "ONE Championship"]
