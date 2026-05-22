"""Round-trip every example videos_config.yaml against the model, plus the
min/max/non-empty-tags bounds the contract promises."""

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
        "searches": [
            {"query": f"test search {i}", "tags": ["educational"]}
            for i in range(10)
        ],
    }


def test_examples_exist() -> None:
    assert _example_paths(), "no apps/*/videos_config.yaml examples found"


@pytest.mark.parametrize("path", _example_paths(), ids=lambda p: p.parent.name)
def test_example_round_trips(path: Path) -> None:
    config = VideosConfig.model_validate(yaml.safe_load(path.read_text()))

    # 1-20 searches, each with at least one tag.
    assert 1 <= len(config.searches) <= 20
    for search in config.searches:
        assert search.query.strip()
        assert search.tags, f"search {search.query!r} has no tags"

    # The set should span the spectrum, not cluster in one or two genres.
    distinct = {tag for search in config.searches for tag in search.tags}
    assert len(distinct) >= 6, f"only {len(distinct)} distinct VideoType tags"


def test_empty_searches_rejected() -> None:
    doc = _base_doc()
    doc["searches"] = []
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_too_many_searches_rejected() -> None:
    doc = _base_doc()
    doc["searches"] = [
        {"query": f"q{i}", "tags": ["fun"]} for i in range(21)
    ]
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_empty_tags_rejected() -> None:
    doc = _base_doc()
    doc["searches"][0]["tags"] = []
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_unknown_video_type_rejected() -> None:
    doc = _base_doc()
    doc["searches"][0]["tags"] = ["not_a_real_genre"]
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_extra_key_rejected() -> None:
    doc = _base_doc()
    doc["unexpected"] = "nope"
    with pytest.raises(ValidationError):
        VideosConfig.model_validate(doc)


def test_video_type_serializes_to_lowercase() -> None:
    assert VideoType.BEHIND_THE_SCENES.value == "behind_the_scenes"
    assert VideoType.PROFESSIONAL.value == "professional"


def test_priority_channels_defaults_to_empty() -> None:
    config = VideosConfig.model_validate(_base_doc())
    assert config.priority_channels == []


def test_priority_channels_captured_when_present() -> None:
    doc = _base_doc()
    doc["priority_channels"] = ["@MyGym", "ONE Championship"]
    config = VideosConfig.model_validate(doc)
    assert config.priority_channels == ["@MyGym", "ONE Championship"]
