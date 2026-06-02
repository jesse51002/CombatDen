"""DB-integration tests — exercise the real ``.sql`` queries against a live,
populated Postgres (the cutover DB).

Skipped unless ``DATABASE_URL`` is set, so the default ``make test`` on a machine
without a DB stays green; CI / a dev with the DB runs them. These hit the actual
queries (incl. the asyncpg array binding in ``load_videos.sql`` /
``insert_gym_feed.sql``) and the router handlers end to end, discovering gym ids
and feed ids at runtime so nothing is hard-coded to a particular data load.

Read-only: every query here is a SELECT; no test mutates the DB.
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import TypeVar

import pytest
from fastapi import HTTPException

import src.api.service.videos_service as vs_module
from schema import FeedPreview, GymDetail, GymsPage, VideosFeed
from src.api import videos_router
from src.api.config import settings
from src.api.errors import NotFoundError
from src.api.service.videos_service import VideosService
from src.shared.database import DirectDatabasePool

pytestmark = pytest.mark.skipif(
    not settings.database_url,
    reason="DATABASE_URL not set; DB-integration tests need the live Postgres",
)

T = TypeVar("T")


def _run_with_service(body: Callable[[VideosService], Awaitable[T]]) -> T:
    """Run ``body(service)`` with a fresh pool+service in its own event loop (the
    async engine is bound to the loop, so it must be created inside asyncio.run)."""

    async def _wrapped() -> T:
        pool = DirectDatabasePool()
        try:
            return await body(VideosService(pool))
        finally:
            await pool.dispose()

    return asyncio.run(_wrapped())


def _run_router(body: Callable[[], Awaitable[T]]) -> T:
    """Point the router's singleton at a fresh DB-backed service for one test,
    run ``body()``, then reset + dispose so the pool never leaks across loops."""

    async def _wrapped() -> T:
        pool = DirectDatabasePool()
        vs_module._DEFAULT = VideosService(pool)
        try:
            return await body()
        finally:
            vs_module._DEFAULT = None
            await pool.dispose()

    return asyncio.run(_wrapped())


async def _first_gym_with_good(service: VideosService):
    """The first gym (by id) that has at least one good video — for feed tests."""
    for gid in await service.list_gyms():
        gym = await service.load_gym(gid)
        if gym.videos.good_video_ids:
            return gym
    raise AssertionError("no gym has any good_video_ids — import data first")


# --- service layer -----------------------------------------------------------


def test_list_gyms_nonempty_and_sorted() -> None:
    async def body(svc: VideosService) -> None:
        gyms = await svc.list_gyms()
        assert gyms, "expected gyms in the DB (run sync-gyms)"
        assert gyms == sorted(gyms)

    _run_with_service(body)


def test_load_gym_roundtrips() -> None:
    async def body(svc: VideosService) -> None:
        first = (await svc.list_gyms())[0]
        gym = await svc.load_gym(first)
        assert gym.gym_id == first
        assert gym.gym_type, "gym_type must be non-empty"
        assert gym.theme
        assert gym.videos.specification.videos_desc
        # has_classes/has_rewards round-trip: None or a non-empty list, never []
        assert gym.classes is None or len(gym.classes) > 0
        assert gym.rewards is None or len(gym.rewards) > 0

    _run_with_service(body)


def test_load_gym_missing_raises_not_found() -> None:
    async def body(svc: VideosService) -> None:
        with pytest.raises(NotFoundError):
            await svc.load_gym("___definitely_not_a_gym___")

    _run_with_service(body)


def test_gyms_page_cards_and_pagination() -> None:
    async def body(svc: VideosService) -> None:
        page1: GymsPage = await svc.list_gyms_page(limit=3, offset=0)
        assert page1.total > 0
        assert page1.limit == 3
        assert len(page1.gyms) <= 3
        for card in page1.gyms:
            assert card.parent_gym_type is not None
            assert card.theme in card.celebration_image_url
            assert card.video_count >= 0
            assert isinstance(card.has_classes, bool)
        if page1.total > 3:
            page2 = await svc.list_gyms_page(limit=3, offset=3)
            ids1 = {c.gym_id for c in page1.gyms}
            ids2 = {c.gym_id for c in page2.gyms}
            assert ids1.isdisjoint(ids2)

    _run_with_service(body)


def test_gyms_page_query_filter() -> None:
    async def body(svc: VideosService) -> None:
        first = (await svc.list_gyms())[0]
        page = await svc.list_gyms_page(limit=100, offset=0, query=first)
        assert any(c.gym_id == first for c in page.gyms)

    _run_with_service(body)


def test_load_videos_preserves_order_and_binds_array() -> None:
    """Exercises load_videos.sql `= ANY(:ids)` (the asyncpg array binding) and
    the requested-order preservation."""

    async def body(svc: VideosService) -> None:
        gym = await _first_gym_with_good(svc)
        wanted = gym.videos.good_video_ids[:5]
        videos = await svc.load_videos(wanted)
        assert videos, "expected the named pool videos to load"
        got_ids = [v.url.split("v=")[-1] for v in videos]
        # every returned id was requested, and in the requested order
        assert got_ids == [i for i in wanted if i in got_ids]

    _run_with_service(body)


# --- router layer ------------------------------------------------------------


def test_router_gym_detail() -> None:
    async def body() -> None:
        first = (await vs_module.videos_service().list_gyms())[0]
        detail = await videos_router.get_gym(first)
        assert isinstance(detail, GymDetail)
        assert detail.gym_id == first
        assert detail.specification.videos_desc

    _run_router(body)


def test_router_gym_detail_404() -> None:
    async def body() -> None:
        with pytest.raises(HTTPException) as exc:
            await videos_router.get_gym("___definitely_not_a_gym___")
        assert exc.value.status_code == 404

    _run_router(body)


def test_router_feed_serves_in_relevance_order() -> None:
    async def body() -> None:
        gym = await _first_gym_with_good(vs_module.videos_service())
        feed: VideosFeed = await videos_router.get_gym_videos(
            gym_id=gym.gym_id,
            video_type=None,
            big_group=None,
            rejected=False,
            limit=20,
            offset=0,
        )
        assert feed.total > 0
        assert feed.videos
        for card in feed.videos:
            assert card.url
        # served ORDER BY relevance_index -> non-decreasing across the page
        rels = [c.relevance_index for c in feed.videos]
        assert rels == sorted(rels)

    _run_router(body)


def test_router_feed_video_type_filter() -> None:
    async def body() -> None:
        gym = await _first_gym_with_good(vs_module.videos_service())
        full = await videos_router.get_gym_videos(
            gym_id=gym.gym_id, video_type=None, big_group=None,
            rejected=False, limit=100, offset=0,
        )
        tagged = next((c for c in full.videos if c.tag is not None), None)
        if tagged is None:
            pytest.skip("no tagged video in this gym's feed")
        filtered = await videos_router.get_gym_videos(
            gym_id=gym.gym_id, video_type=tagged.tag, big_group=None,
            rejected=False, limit=100, offset=0,
        )
        assert filtered.videos
        assert all(c.tag == tagged.tag for c in filtered.videos)

    _run_router(body)


def test_router_feed_both_filters_is_400() -> None:
    async def body() -> None:
        gym = await _first_gym_with_good(vs_module.videos_service())
        full = await videos_router.get_gym_videos(
            gym_id=gym.gym_id, video_type=None, big_group=None,
            rejected=False, limit=100, offset=0,
        )
        tagged = next((c for c in full.videos if c.tag is not None), None)
        if tagged is None:
            pytest.skip("no tagged video to derive a big_group from")
        with pytest.raises(HTTPException) as exc:
            await videos_router.get_gym_videos(
                gym_id=gym.gym_id, video_type=tagged.tag, big_group=tagged.big_group,
                rejected=False, limit=100, offset=0,
            )
        assert exc.value.status_code == 400

    _run_router(body)


def test_router_preview_sections_capped() -> None:
    async def body() -> None:
        gym = await _first_gym_with_good(vs_module.videos_service())
        preview: FeedPreview = await videos_router.get_gym_videos_preview(
            gym_id=gym.gym_id, rejected=False, per_tag=3
        )
        assert preview.sections
        for section in preview.sections:
            assert len(section.videos) <= 3
            assert all(c.tag == section.tag for c in section.videos)

    _run_router(body)
