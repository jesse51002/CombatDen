"""The read-only endpoints (single-tenant): gym browser + per-theme videos /
classes / rewards. Calls the handler coroutines directly (the suite has no httpx
/ TestClient), pointing the module singleton at a tmp data root. The limit/offset
422 validation is enforced by FastAPI's Query layer, not the handler, so it's
covered by the live verification in the README rather than here."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
from fastapi import HTTPException

import src.api.service.videos_service as vs_module
from schema import (
    BigGroup,
    ClassImage,
    Gym,
    GymSpecifications,
    GymVideos,
    RewardCard,
    VideoOutput,
    VideoType,
)
from schema.gym_type import GymType
from src.api import videos_router
from src.api.service.videos_service import VideosService


def _video(vid: str, *, relevance: int, tag: str | None) -> VideoOutput:
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
    )


def _seed_pool(service: VideosService) -> None:
    """A pool with a mix of genres (and one untagged)."""
    asyncio.run(
        service.save_pool(
            [
                _video("edu1", relevance=0, tag="educational"),
                _video("edu2", relevance=1, tag="analysis"),
                _video("ent1", relevance=2, tag="memes"),
                _video("bad1", relevance=3, tag="memes"),
                _video("new1", relevance=4, tag=None),
            ]
        )
    )


def _class_cards(n: int = 4) -> list[ClassImage]:
    return [
        ClassImage(
            name=f"Class {i}",
            image_url=f"https://img/{i}.jpg",
            description=f"About class {i}.",
            instructor_name=f"Coach {i}",
            instructor_bio=f"Bio {i}.",
            instructor_image_url=f"https://img/coach{i}.jpg",
        )
        for i in range(n)
    ]


def _reward_cards(n: int = 3) -> list[RewardCard]:
    return [
        RewardCard(
            title=f"Reward {i}",
            image_url=f"https://img/r{i}.jpg",
            price_label="Free",
            points_cost=500 * (i + 1),
        )
        for i in range(n)
    ]


def _write_gym(
    service: VideosService,
    *,
    design: str = "ZZUndoneVinyasaFlow",
    gym_id: str = "vinyasa",
    gym_type: list[GymType] | None = None,
    good: tuple[str, ...] = ("ent1", "edu1"),
    rejected: tuple[str, ...] = ("bad1",),
    classes: list[ClassImage] | None = None,
    rewards: list[RewardCard] | None = None,
) -> None:
    """Write one gym carrying its theme + videos/classes/rewards (the gym files
    ARE the theme->gym mapping; there is no theme_gym.yaml)."""
    asyncio.run(
        service.save_gym(
            Gym(
                gym_id=gym_id,
                gym_type=gym_type or [GymType.VINYASA],
                theme=design,
                videos=GymVideos(
                    specification=GymSpecifications(
                        videos_desc="flow classes", avoid_desc="no injuries"
                    ),
                    good_video_ids=list(good),
                    rejected_video_ids=list(rejected),
                ),
                classes=classes,
                rewards=rewards,
            )
        )
    )


@pytest.fixture
def service(tmp_path: Path) -> VideosService:
    svc = VideosService(root=tmp_path)
    vs_module._DEFAULT = svc  # point the router's process-scoped singleton at tmp
    return svc


@pytest.fixture(autouse=True)
def _restore_singleton():
    yield
    vs_module._DEFAULT = None  # don't leak the tmp-tree service into other tests


def _ids(feed) -> list[str]:
    return [c.url.split("v=")[1] for c in feed.videos]


# --- fetch-by-theme videos ---------------------------------------------------


def _get_theme(**kwargs):
    params = dict(
        design_id="ZZUndoneVinyasaFlow",
        video_type=None,
        big_group=None,
        limit=20,
        offset=0,
    )
    params.update(kwargs)
    return asyncio.run(videos_router.get_theme_videos(**params))


def test_theme_feed_serves_only_gym_good_in_order(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("ent1", "edu1"))
    feed = _get_theme()
    # Only the gym's good ids, in good_video_ids order (not pool relevance order).
    assert _ids(feed) == ["ent1", "edu1"]
    assert feed.total == 2


def test_theme_feed_serves_exactly_the_gym_good_list(service: VideosService) -> None:
    _seed_pool(service)
    # Approval is the gym's good list — the pool has no opinion.
    _write_gym(service, good=("bad1",))
    assert _ids(_get_theme()) == ["bad1"]


def test_theme_feed_skips_ids_not_in_pool(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "ghost999"))
    assert _ids(_get_theme()) == ["edu1"]  # ghost id not in the pool -> skipped


def test_theme_feed_unmapped_design_is_404(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service)
    with pytest.raises(HTTPException) as exc:
        _get_theme(design_id="ZZUndoneUnknown")
    assert exc.value.status_code == 404


def test_theme_feed_video_type_filter(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "edu2", "ent1"))
    feed = _get_theme(video_type=VideoType.EDUCATIONAL)
    assert _ids(feed) == ["edu1"]  # only the educational-tagged good video


def test_theme_feed_both_filters_is_400(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service)
    with pytest.raises(HTTPException) as exc:
        _get_theme(video_type=VideoType.EDUCATIONAL, big_group=BigGroup.EDUCATIONAL)
    assert exc.value.status_code == 400


# --- gym browser -------------------------------------------------------------


def _get_gyms(**kwargs):
    params = dict(query=None, limit=20, offset=0)
    params.update(kwargs)
    return asyncio.run(videos_router.get_gyms(**params))


def test_gyms_page_returns_cards(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "ent1"), classes=_class_cards())
    page = _get_gyms()
    assert page.total == 1
    card = page.gyms[0]
    assert card.gym_id == "vinyasa"
    assert card.theme == "ZZUndoneVinyasaFlow"
    assert card.parent_gym_type.value == "Yoga"  # coarse bucket from vinyasa
    assert (
        card.celebration_image_url
        == "/apps/combatden/ZZUndoneVinyasaFlow/images/celebration_image"
    )
    assert card.video_count == 2  # len(good_video_ids)
    assert card.has_classes is True
    assert card.has_rewards is False


def test_gyms_page_paginates(service: VideosService) -> None:
    _seed_pool(service)
    for gid, design in [("vinyasa", "T1"), ("mma", "T2"), ("boxing", "T3")]:
        _write_gym(service, design=design, gym_id=gid)
    first = _get_gyms(limit=2, offset=0)
    assert first.total == 3 and len(first.gyms) == 2
    second = _get_gyms(limit=2, offset=2)
    assert second.total == 3 and len(second.gyms) == 1
    assert second.gyms[0].gym_id == "vinyasa"  # boxing, mma, vinyasa -> offset 2


def test_gyms_page_empty_when_no_gyms(service: VideosService) -> None:
    _seed_pool(service)  # pool exists, but no gyms written
    page = _get_gyms()
    assert page.total == 0 and page.gyms == []


def test_gyms_page_query_filters(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, design="ZZUndoneVinyasaFlow", gym_id="vinyasa")
    _write_gym(service, design="ApexMMA", gym_id="mma", gym_type=[GymType.MMA])
    page = _get_gyms(query="mma")
    assert page.total == 1
    assert page.gyms[0].gym_id == "mma"


# --- classes / rewards -------------------------------------------------------


def test_theme_classes_resolves_from_gym(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, classes=_class_cards())
    out = asyncio.run(videos_router.get_theme_classes("ZZUndoneVinyasaFlow"))
    assert len(out.classes) == 4


def test_theme_classes_none_is_404(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service)  # no classes authored
    with pytest.raises(HTTPException) as exc:
        asyncio.run(videos_router.get_theme_classes("ZZUndoneVinyasaFlow"))
    assert exc.value.status_code == 404


def test_theme_classes_unmapped_design_is_404(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, classes=_class_cards())
    with pytest.raises(HTTPException) as exc:
        asyncio.run(videos_router.get_theme_classes("ZZUndoneUnknown"))
    assert exc.value.status_code == 404


def test_theme_rewards_resolves_from_gym(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service, rewards=_reward_cards())
    out = asyncio.run(videos_router.get_theme_rewards("ZZUndoneVinyasaFlow"))
    assert len(out.rewards) == 3
    assert out.rewards[0].price_label == "Free"


def test_theme_rewards_none_is_404(service: VideosService) -> None:
    _seed_pool(service)
    _write_gym(service)  # no rewards authored
    with pytest.raises(HTTPException) as exc:
        asyncio.run(videos_router.get_theme_rewards("ZZUndoneVinyasaFlow"))
    assert exc.value.status_code == 404
