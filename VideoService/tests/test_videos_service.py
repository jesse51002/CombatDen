"""VideosService filesystem behaviour, driven against a tmp apps tree.

Uses ``asyncio.run`` so the suite needs only pytest (no pytest-asyncio / httpx)."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import VideosService

_VALID_YAML = """\
company_name: Demo Co
type: Demo niche
videos_desc: Videos worth surfacing.
avoid_desc: Content to avoid.
searches:
""" + "".join(
    f"  - query: demo search {i}\n    tags: [educational]\n" for i in range(10)
)


_VALID_OUTPUT_YAML = """\
company_name: Demo Co
app_id: alpha
generated_at: 2026-05-22T00:00:00Z
quota_units_estimate: 102
videos:
  - url: https://www.youtube.com/watch?v=abc
    title: A video
    description: a description kept for validation
    thumbnail_url: https://i.ytimg.com/vi/abc/hqdefault.jpg
    channel_name: Some Channel
    channel_url: https://www.youtube.com/channel/c1
    channel_avatar_url: https://yt3.ggpht.com/pfp
    view_count: 1000
    like_count: 50
    tags: [educational]
    source_queries: [demo search]
    relevance_index: 0
"""


_VALID_CLASS_YAML = """\
company_name: Demo Co
app_id: alpha
classes:
""" + "".join(
    f"  - name: Class {i}\n"
    f"    image_url: https://img/{i}.jpg\n"
    f"    description: About class {i}.\n"
    f"    instructor_name: Coach {i}\n"
    f"    instructor_bio: Bio {i}.\n"
    f"    instructor_image_url: https://img/coach{i}.jpg\n"
    for i in range(4)
)


def _write_company(apps_root: Path, app_id: str, body: str) -> None:
    (apps_root / app_id).mkdir(parents=True)
    (apps_root / app_id / "videos_config.yaml").write_text(body)


def _write_output(apps_root: Path, app_id: str, body: str) -> None:
    (apps_root / app_id).mkdir(parents=True, exist_ok=True)
    (apps_root / app_id / "videos_output.yaml").write_text(body)


def test_list_apps_only_dirs_with_config(tmp_path: Path) -> None:
    _write_company(tmp_path, "alpha", _VALID_YAML)
    _write_company(tmp_path, "bravo", _VALID_YAML)
    (tmp_path / "empty_dir").mkdir()  # no config -> excluded
    service = VideosService(apps_root=tmp_path)

    assert asyncio.run(service.list_apps()) == ["alpha", "bravo"]


def test_list_apps_empty_tree(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path / "does_not_exist")
    assert asyncio.run(service.list_apps()) == []


def test_load_returns_validated_config(tmp_path: Path) -> None:
    _write_company(tmp_path, "alpha", _VALID_YAML)
    service = VideosService(apps_root=tmp_path)

    config = asyncio.run(service.load("alpha"))
    assert config.company_name == "Demo Co"
    assert len(config.searches) == 10


def test_load_missing_company_raises_not_found(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load("ghost"))


def test_load_stale_config_raises_invalid(tmp_path: Path) -> None:
    _write_company(tmp_path, "alpha", "company_name: only\n")  # missing fields
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(InvalidConfigError):
        asyncio.run(service.load("alpha"))


@pytest.mark.parametrize("bad_id", ["../escape", "Bad", "a/b", ".hidden"])
def test_malformed_app_id_raises_not_found(tmp_path: Path, bad_id: str) -> None:
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load(bad_id))


def test_load_output_returns_validated_output(tmp_path: Path) -> None:
    _write_output(tmp_path, "alpha", _VALID_OUTPUT_YAML)
    service = VideosService(apps_root=tmp_path)

    output = asyncio.run(service.load_output("alpha"))
    assert output.app_id == "alpha"
    assert len(output.videos) == 1
    assert output.videos[0].view_count == 1000


def test_load_output_missing_file_raises_not_found(tmp_path: Path) -> None:
    # Company has a brief but was never run through the batch script.
    _write_company(tmp_path, "alpha", _VALID_YAML)
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load_output("alpha"))


def test_load_output_stale_raises_invalid(tmp_path: Path) -> None:
    _write_output(tmp_path, "alpha", "company_name: only\n")  # missing fields
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(InvalidConfigError):
        asyncio.run(service.load_output("alpha"))


def test_load_classes_returns_validated(tmp_path: Path) -> None:
    (tmp_path / "alpha").mkdir(parents=True)
    (tmp_path / "alpha" / "class_output.yaml").write_text(_VALID_CLASS_YAML)
    service = VideosService(apps_root=tmp_path)

    out = asyncio.run(service.load_classes("alpha"))
    assert len(out.classes) == 4
    assert out.classes[0].image_url == "https://img/0.jpg"


def test_load_classes_missing_raises_not_found(tmp_path: Path) -> None:
    _write_company(tmp_path, "alpha", _VALID_YAML)  # brief but no class_output.yaml
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load_classes("alpha"))
