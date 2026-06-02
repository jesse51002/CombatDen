"""The read-only endpoints (gym browser + per-gym videos / classes / rewards).

Unit tests: they call the handler coroutines directly (no httpx / TestClient) with
the router's process-scoped singleton pointed at an in-memory ``FakeVideosService``
(no database). They exercise the ROUTER's logic — feed filters, pagination, the
rejected-list switch, avatar backfill, preview grouping/capping, 404, and the
GymDetail projection. The SQL itself (incl. relevance ordering) is covered by
``test_integration_db.py``. The limit/offset 422 validation lives in FastAPI's
Query layer, not the handler, so it's verified live rather than here.
"""

from __future__ import annotations

import asyncio

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
from tests.fakes import FakeVideosService


def _video(
    vid: str, *, relevance: int, tag: str | None, avatar: str = "a"
) -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="d",
        thumbnail_url="t",
        channel_name="Some Channel",
        channel_url="cu",
        channel_avatar_url=avatar,
        source_queries=["q"],
        relevance_index=relevance,
        tag=tag,
    )


def _seed_pool(service: FakeVideosService) -> None:
    """A pool with a mix of genres (and one untagged)."""
    service.add_videos(
        [
            _video("edu1", relevance=0, tag="educational"),
            _video("edu2", relevance=1, tag="analysis"),
            _video("ent1", relevance=2, tag="memes"),
            _video("bad1", relevance=3, tag="memes"),
            _video("new1", relevance=4, tag=None),
        ]
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
    service: FakeVideosService,
    *,
    design: str = "VinyasaFlow",
    gym_id: str = "vinyasa",
    gym_type: list[GymType] | None = None,
    good: tuple[str, ...] = ("ent1", "edu1"),
    rejected: tuple[str, ...] = ("bad1",),
    classes: list[ClassImage] | None = None,
    rewards: list[RewardCard] | None = None,
) -> None:
    """Add one gym carrying its theme + videos/classes/rewards (the gym files ARE
    the theme->gym mapping)."""
    service.add_gym(
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


@pytest.fixture
def service() -> FakeVideosService:
    svc = FakeVideosService()
    vs_module._DEFAULT = svc  # point the router's process-scoped singleton at it
    return svc


@pytest.fixture(autouse=True)
def _restore_singleton(monkeypatch: pytest.MonkeyPatch):
    # The celebration URL setting now defaults to the prod CDN; these unit tests
    # assert the ThemeService-relative fallback, so select the local path
    # explicitly. The CDN behaviour has its own test below.
    monkeypatch.setattr(vs_module.settings, "assets_cdn_base_url", "")
    yield
    vs_module._DEFAULT = None  # don't leak the fake into other tests


def _ids(feed) -> list[str]:
    return [c.url.split("v=")[1] for c in feed.videos]


# --- fetch-by-gym videos -----------------------------------------------------


def _get_gym_videos(**kwargs):
    params = dict(
        gym_id="vinyasa",
        video_type=None,
        big_group=None,
        rejected=False,
        limit=20,
        offset=0,
    )
    params.update(kwargs)
    return asyncio.run(videos_router.get_gym_videos(**params))


def test_gym_feed_serves_gym_good_in_relevance_order(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("ent1", "edu1"))
    feed = _get_gym_videos()
    # The gym's good ids, served in relevance_index order (edu1=0 before ent1=2),
    # not the authored good-list order. (Ordering is the SQL service's job.)
    assert _ids(feed) == ["edu1", "ent1"]
    assert feed.total == 2


def test_gym_feed_serves_exactly_the_gym_good_list(service: FakeVideosService) -> None:
    _seed_pool(service)
    # Approval is the gym's good list — the pool has no opinion.
    _write_gym(service, good=("bad1",))
    assert _ids(_get_gym_videos()) == ["bad1"]


def test_gym_feed_skips_ids_not_in_pool(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "ghost999"))
    assert _ids(_get_gym_videos()) == ["edu1"]  # ghost id not in pool -> skipped


def test_gym_feed_unknown_gym_is_404(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service)
    with pytest.raises(HTTPException) as exc:
        _get_gym_videos(gym_id="nope")
    assert exc.value.status_code == 404


def test_gym_feed_rejected_serves_rejected_list(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("ent1", "edu1"), rejected=("bad1", "edu2"))
    # Default (approved) feed is the gym's good list, in relevance order...
    assert _ids(_get_gym_videos()) == ["edu1", "ent1"]
    # ...and rejected=True swaps it for the rejected list (edu2=1 before bad1=3).
    feed = _get_gym_videos(rejected=True)
    assert _ids(feed) == ["edu2", "bad1"]
    assert feed.total == 2


def _get_preview(**kwargs):
    params = dict(gym_id="vinyasa", rejected=False, per_tag=10)
    params.update(kwargs)
    return asyncio.run(videos_router.get_gym_videos_preview(**params))


def test_preview_one_section_per_tag_in_feed_order(service: FakeVideosService) -> None:
    _seed_pool(service)
    # edu1=educational, edu2=analysis, ent1=memes -> 3 sections, feed order.
    _write_gym(service, good=("edu1", "edu2", "ent1"))
    preview = _get_preview()
    assert [s.tag.value for s in preview.sections] == [
        "educational",
        "analysis",
        "memes",
    ]
    assert all(len(s.videos) >= 1 for s in preview.sections)


def test_preview_caps_videos_per_tag(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("ent1", "bad1"))  # both memes
    preview = _get_preview(per_tag=1)
    assert len(preview.sections) == 1
    assert preview.sections[0].tag.value == "memes"
    assert len(preview.sections[0].videos) == 1  # capped at per_tag


def test_preview_rejected_uses_rejected_list(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1",), rejected=("ent1", "bad1"))  # rejected: memes
    preview = _get_preview(rejected=True)
    assert [s.tag.value for s in preview.sections] == ["memes"]
    assert len(preview.sections[0].videos) == 2


def test_gym_feed_video_type_filter(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "edu2", "ent1"))
    feed = _get_gym_videos(video_type=VideoType.EDUCATIONAL)
    assert _ids(feed) == ["edu1"]  # only the educational-tagged good video


def test_gym_feed_both_filters_is_400(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service)
    with pytest.raises(HTTPException) as exc:
        _get_gym_videos(video_type=VideoType.EDUCATIONAL, big_group=BigGroup.EDUCATIONAL)
    assert exc.value.status_code == 400


# --- empty-avatar backfill (serve-time instructor-headshot fallback) ---------


def _seed_empty_avatar_pool(service: FakeVideosService) -> None:
    """A pool whose videos have no channel avatar — the real-world case (Apify
    never returned them)."""
    service.add_videos(
        [
            _video("edu1", relevance=0, tag="educational", avatar=""),
            _video("ent1", relevance=1, tag="memes", avatar=""),
        ]
    )


def test_feed_backfills_empty_avatars_from_instructors(
    service: FakeVideosService,
) -> None:
    _seed_empty_avatar_pool(service)
    classes = _class_cards()
    _write_gym(service, good=("edu1", "ent1"), classes=classes)
    feed = _get_gym_videos()
    pool = {c.instructor_image_url for c in classes}
    assert feed.videos and all(c.channel_avatar_url in pool for c in feed.videos)


def test_feed_keeps_a_real_avatar(service: FakeVideosService) -> None:
    service.add_videos(
        [_video("edu1", relevance=0, tag="educational", avatar="https://real/a.jpg")]
    )
    _write_gym(service, good=("edu1",), classes=_class_cards())
    feed = _get_gym_videos()
    assert feed.videos[0].channel_avatar_url == "https://real/a.jpg"


def test_feed_no_classes_leaves_avatar_empty(service: FakeVideosService) -> None:
    _seed_empty_avatar_pool(service)
    _write_gym(service, good=("edu1",))  # no classes authored -> nothing to fill from
    feed = _get_gym_videos()
    assert feed.videos[0].channel_avatar_url == ""


def test_preview_backfills_empty_avatars(service: FakeVideosService) -> None:
    _seed_empty_avatar_pool(service)
    classes = _class_cards()
    _write_gym(service, good=("edu1", "ent1"), classes=classes)
    preview = _get_preview()
    pool = {c.instructor_image_url for c in classes}
    cards = [c for s in preview.sections for c in s.videos]
    assert cards and all(c.channel_avatar_url in pool for c in cards)


# --- gym browser -------------------------------------------------------------


def _get_gyms(**kwargs):
    params = dict(query=None, limit=20, offset=0)
    params.update(kwargs)
    return asyncio.run(videos_router.get_gyms(**params))


def test_gyms_page_returns_cards(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, good=("edu1", "ent1"), classes=_class_cards())
    page = _get_gyms()
    assert page.total == 1
    card = page.gyms[0]
    assert card.gym_id == "vinyasa"
    assert card.theme == "VinyasaFlow"
    assert card.parent_gym_type.value == "Yoga"  # coarse bucket from vinyasa
    assert (
        card.celebration_image_url
        == "/apps/combatden/VinyasaFlow/images/celebration_image"
    )
    assert card.video_count == 2  # len(good_video_ids)
    assert card.has_classes is True
    assert card.has_rewards is False


def test_gym_card_celebration_url_uses_cdn_when_configured(
    service: FakeVideosService, monkeypatch: pytest.MonkeyPatch
) -> None:
    """With a CDN base set (the default in prod), the gym card's celebration URL
    is an absolute CDN link mirroring ThemeService's object-key scheme."""
    monkeypatch.setattr(
        vs_module.settings, "assets_cdn_base_url", "https://cdn.test"
    )
    _seed_pool(service)
    _write_gym(service, good=("edu1", "ent1"), classes=_class_cards())
    card = _get_gyms().gyms[0]
    assert (
        card.celebration_image_url
        == "https://cdn.test/themes/combatden/VinyasaFlow/images/celebration_image.png"
    )


def test_gyms_page_paginates(service: FakeVideosService) -> None:
    _seed_pool(service)
    for gid, design in [("vinyasa", "T1"), ("mma", "T2"), ("boxing", "T3")]:
        _write_gym(service, design=design, gym_id=gid)
    first = _get_gyms(limit=2, offset=0)
    assert first.total == 3 and len(first.gyms) == 2
    second = _get_gyms(limit=2, offset=2)
    assert second.total == 3 and len(second.gyms) == 1
    assert second.gyms[0].gym_id == "vinyasa"  # boxing, mma, vinyasa -> offset 2


def test_gyms_page_empty_when_no_gyms(service: FakeVideosService) -> None:
    _seed_pool(service)  # pool exists, but no gyms written
    page = _get_gyms()
    assert page.total == 0 and page.gyms == []


def test_gyms_page_query_filters(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service, design="VinyasaFlow", gym_id="vinyasa")
    _write_gym(service, design="ApexMMA", gym_id="mma", gym_type=[GymType.MMA])
    page = _get_gyms(query="mma")
    assert page.total == 1
    assert page.gyms[0].gym_id == "mma"


# --- gym detail (classes / rewards / spec, one fetch) ------------------------


def test_gym_detail_resolves_classes_rewards_and_spec(
    service: FakeVideosService,
) -> None:
    _seed_pool(service)
    _write_gym(service, classes=_class_cards(), rewards=_reward_cards())
    out = asyncio.run(videos_router.get_gym("vinyasa"))
    assert out.gym_id == "vinyasa"
    assert out.theme == "VinyasaFlow"  # carried for branding
    assert len(out.classes) == 4
    assert len(out.rewards) == 3
    assert out.rewards[0].price_label == "Free"
    # The feed spec rides along — no separate fetch.
    assert out.specification.videos_desc == "flow classes"
    assert out.specification.avoid_desc == "no injuries"


def test_gym_detail_classes_rewards_none_when_unauthored(
    service: FakeVideosService,
) -> None:
    _seed_pool(service)
    _write_gym(service)  # no classes / rewards authored
    out = asyncio.run(videos_router.get_gym("vinyasa"))
    assert out.classes is None
    assert out.rewards is None


def test_gym_detail_unknown_gym_is_404(service: FakeVideosService) -> None:
    _seed_pool(service)
    _write_gym(service)
    with pytest.raises(HTTPException) as exc:
        asyncio.run(videos_router.get_gym("nope"))
    assert exc.value.status_code == 404
