"""The /videos endpoint logic: filtering, pagination, and the mutually-exclusive
filter guard. Calls the handler coroutine directly (the suite has no httpx /
TestClient), pointing the module singleton at a tmp apps tree. The limit/offset
422 validation is enforced by FastAPI's Query layer, not the handler, so it is
covered by the live verification in the README rather than here."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import pytest
from fastapi import HTTPException

import src.api.service.videos_service as vs_module
from schema import BigGroup, VideoOutput, VideosOutput, VideoType
from src.api import videos_router
from src.api.service.videos_service import VideosService


def _video(vid: str, *, relevance: int, tag: str | None, is_good: bool | None) -> VideoOutput:
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
        tag=tag,
        is_good=is_good,
    )


def _seed(tmp_path: Path) -> None:
    """A feed with: 2 educational (good), 1 entertainment (good), 1 off-niche
    (is_good False), 1 unclassified (tag None)."""
    output = VideosOutput(
        company_name="Demo Co",
        app_id="alpha",
        generated_at=datetime(2026, 5, 22, tzinfo=timezone.utc),
        quota_units_estimate=102,
        videos=[
            _video("edu1", relevance=0, tag="educational", is_good=True),
            _video("edu2", relevance=1, tag="analysis", is_good=True),
            _video("ent1", relevance=2, tag="memes", is_good=True),
            _video("bad1", relevance=3, tag="memes", is_good=False),
            _video("new1", relevance=4, tag=None, is_good=None),
        ],
    )
    service = VideosService(apps_root=tmp_path)
    asyncio.run(service.save_output("alpha", output))
    # Point the router's process-scoped singleton at this tmp tree.
    vs_module._DEFAULT = service


def _ids(feed) -> list[str]:
    return [c.url.split("v=")[1] for c in feed.videos]


def _get(**kwargs):
    params = dict(app_id="alpha", video_type=None, big_group=None, limit=20, offset=0)
    params.update(kwargs)
    return asyncio.run(videos_router.get_videos(**params))


@pytest.fixture(autouse=True)
def _restore_singleton():
    yield
    vs_module._DEFAULT = None  # don't leak the tmp-tree service into other tests


def test_drops_off_niche_keeps_unclassified(tmp_path: Path) -> None:
    _seed(tmp_path)
    feed = _get()
    # bad1 (is_good False) excluded; new1 (unclassified) still served.
    assert _ids(feed) == ["edu1", "edu2", "ent1", "new1"]
    assert feed.total == 4
    assert feed.limit == 20
    assert feed.offset == 0


def test_pagination_slices_and_reports_total(tmp_path: Path) -> None:
    _seed(tmp_path)
    feed = _get(limit=2, offset=2)
    assert _ids(feed) == ["ent1", "new1"]
    assert feed.total == 4  # total is the match count, not the page size
    assert feed.limit == 2
    assert feed.offset == 2


def test_video_type_filter(tmp_path: Path) -> None:
    _seed(tmp_path)
    feed = _get(video_type=VideoType.ANALYSIS)
    assert _ids(feed) == ["edu2"]
    assert feed.total == 1


def test_big_group_filter_excludes_unclassified(tmp_path: Path) -> None:
    _seed(tmp_path)
    feed = _get(big_group=BigGroup.EDUCATIONAL)
    # educational + analysis map to the educational group; new1 (tag None) is out.
    assert _ids(feed) == ["edu1", "edu2"]
    feed = _get(big_group=BigGroup.ENTERTAINMENT)
    assert _ids(feed) == ["ent1"]


def test_both_filters_is_400(tmp_path: Path) -> None:
    _seed(tmp_path)
    with pytest.raises(HTTPException) as exc:
        _get(video_type=VideoType.Memes, big_group=BigGroup.ENTERTAINMENT)
    assert exc.value.status_code == 400
