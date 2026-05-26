"""VideosService filesystem behaviour, driven against a tmp apps tree.

Uses ``asyncio.run`` so the suite needs only pytest (no pytest-asyncio / httpx)."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import pytest

from schema import VideoOutput, VideosOutput
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import VideosService

_VALID_YAML = """\
company_name: Demo Co
type: Demo niche
videos_desc: Videos worth surfacing.
avoid_desc: Content to avoid.
searches:
""" + "".join(
    f"  - query: demo search {i}\n" for i in range(10)
)


def _video(vid: str, *, relevance: int = 0, **overrides: object) -> VideoOutput:
    """A minimal valid VideoOutput keyed by ``vid`` (its url's v param)."""
    fields: dict[str, object] = dict(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="a description kept for validation",
        thumbnail_url=f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
        channel_name="Some Channel",
        channel_url="https://www.youtube.com/channel/c1",
        channel_avatar_url="https://yt3.ggpht.com/pfp",
        view_count=1000,
        like_count=50,
        source_queries=["demo search"],
        relevance_index=relevance,
    )
    fields.update(overrides)
    return VideoOutput(**fields)


def _output(*videos: VideoOutput) -> VideosOutput:
    return VideosOutput(
        company_name="Demo Co",
        app_id="alpha",
        generated_at=datetime(2026, 5, 22, tzinfo=timezone.utc),
        quota_units_estimate=102,
        videos=list(videos),
    )


def _save(service: VideosService, output: VideosOutput) -> None:
    asyncio.run(service.save_output(output.app_id, output))


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


def _write_manifest(apps_root: Path, app_id: str, body: str) -> None:
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


def test_save_output_then_load_round_trip(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(service, _output(_video("abc", relevance=0), _video("xyz", relevance=1)))

    output = asyncio.run(service.load_output("alpha"))
    assert output.app_id == "alpha"
    assert output.company_name == "Demo Co"
    assert output.quota_units_estimate == 102
    assert len(output.videos) == 2
    assert output.videos[0].view_count == 1000


def test_save_output_writes_manifest_and_per_video_files(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(service, _output(_video("abc"), _video("xyz", relevance=1)))

    # Manifest holds metadata only — no inline videos list.
    manifest_text = (tmp_path / "alpha" / "videos_output.yaml").read_text()
    assert "videos:" not in manifest_text
    assert "quota_units_estimate" in manifest_text
    # One file per video, named by id; transcript is the last key.
    assert asyncio.run(service.list_video_ids("alpha")) == ["abc", "xyz"]
    abc_text = (tmp_path / "alpha" / "videos" / "abc.yaml").read_text()
    assert abc_text.rstrip().splitlines()[-1].startswith("transcript:")


def test_load_output_sorted_by_relevance_then_id(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(
        service,
        _output(
            _video("zzz", relevance=2),
            _video("aaa", relevance=0),
            _video("mmm", relevance=0),
        ),
    )
    ids = [v.url.split("v=")[1] for v in asyncio.run(service.load_output("alpha")).videos]
    assert ids == ["aaa", "mmm", "zzz"]  # (relevance, id) order


def test_save_output_replaces_stale_video_files(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(service, _output(_video("abc"), _video("xyz", relevance=1)))
    _save(service, _output(_video("abc")))  # xyz dropped on a fresh fetch

    assert asyncio.run(service.list_video_ids("alpha")) == ["abc"]


def test_save_video_partial_update_leaves_others(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(service, _output(_video("abc"), _video("xyz", relevance=1)))

    updated = _video("abc", transcript="full transcript text")
    asyncio.run(service.save_video("alpha", updated))

    output = asyncio.run(service.load_output("alpha"))
    by_id = {v.url.split("v=")[1]: v for v in output.videos}
    assert by_id["abc"].transcript == "full transcript text"
    assert by_id["xyz"].transcript is None  # untouched
    assert output.quota_units_estimate == 102  # manifest untouched


def test_delete_video_removes_file(tmp_path: Path) -> None:
    service = VideosService(apps_root=tmp_path)
    _save(service, _output(_video("abc"), _video("xyz", relevance=1)))

    assert asyncio.run(service.delete_video("alpha", "xyz")) is True
    assert asyncio.run(service.delete_video("alpha", "nope")) is False
    assert asyncio.run(service.list_video_ids("alpha")) == ["abc"]


def test_load_output_missing_manifest_raises_not_found(tmp_path: Path) -> None:
    # Company has a brief but was never run through the batch script.
    _write_company(tmp_path, "alpha", _VALID_YAML)
    service = VideosService(apps_root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load_output("alpha"))


def test_load_output_stale_manifest_raises_invalid(tmp_path: Path) -> None:
    _write_manifest(tmp_path, "alpha", "company_name: only\n")  # missing fields
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
