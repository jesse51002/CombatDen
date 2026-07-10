"""Feed-learning refine runner + the router wiring that fires it.

Pure unit tests (no DB / network):

* ``VideoFeedRefineRunner`` — ``start`` fires a detached refine; per-gym
  COALESCED (a second ``start`` for an in-flight gym is dropped, and the guard
  clears when the refine finishes so a later curation fires afresh); a refine
  failure never propagates; ``drain`` cancels + clears in-flight work.
* The router wiring — a manual REJECT (``remove_gym_video`` ``owner=False``) and a
  KEEP (``keep_gym_video``) fire the runner; an owner-section remove
  (``owner=True``) does NOT; owner-add spawns no refine at all.
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.videos.service.video_feed_refine_runner import VideoFeedRefineRunner
from src.videos.videos_router import (
    add_gym_video,
    keep_gym_video,
    remove_gym_video,
)


def _reset_runner() -> None:
    """Clear the ClassVar-backed task + in-flight sets between tests."""
    VideoFeedRefineRunner._background_runs.clear()
    VideoFeedRefineRunner._in_flight_gyms.clear()


async def _await_background() -> None:
    """Await every in-flight refine task to completion (without cancelling)."""
    runs = list(VideoFeedRefineRunner._background_runs)
    for run in runs:
        await asyncio.gather(run, return_exceptions=True)


class _CountingRefiner:
    """A ``VideoFeedRefiner`` stand-in that records each gym refined + returns."""

    def __init__(self) -> None:
        self.calls: list = []

    async def refine_from_feed(self, gym_id):  # noqa: ANN001, ANN201
        self.calls.append(gym_id)
        return None


class _GatedRefiner:
    """A refiner that blocks on an event so a test can hold a refine in flight."""

    def __init__(self) -> None:
        self.calls: list = []
        self.gate = asyncio.Event()

    async def refine_from_feed(self, gym_id):  # noqa: ANN001, ANN201
        self.calls.append(gym_id)
        await self.gate.wait()
        return None


# ── runner: fire + per-gym coalescing ────────────────────────────


@pytest.mark.asyncio
async def test_start_fires_refine_and_reclears_after() -> None:
    _reset_runner()
    refiner = _CountingRefiner()
    runner = VideoFeedRefineRunner(refiner)
    gym = uuid4()

    runner.start(gym)
    await _await_background()

    assert refiner.calls == [gym]
    assert gym not in VideoFeedRefineRunner._in_flight_gyms
    # window closed once the refine finished → a later curation fires afresh.
    runner.start(gym)
    await _await_background()
    assert refiner.calls == [gym, gym]


@pytest.mark.asyncio
async def test_start_coalesces_concurrent_same_gym() -> None:
    _reset_runner()
    refiner = _GatedRefiner()
    runner = VideoFeedRefineRunner(refiner)
    gym = uuid4()

    runner.start(gym)
    runner.start(gym)  # dropped — a refine for this gym is already in flight
    runner.start(gym)  # dropped
    await asyncio.sleep(0)  # let the one scheduled task reach its gate

    assert refiner.calls == [gym]  # coalesced to a single in-flight refine
    assert len(VideoFeedRefineRunner._background_runs) == 1

    refiner.gate.set()
    await _await_background()


@pytest.mark.asyncio
async def test_start_independent_across_gyms() -> None:
    _reset_runner()
    refiner = _GatedRefiner()
    runner = VideoFeedRefineRunner(refiner)
    g1, g2 = uuid4(), uuid4()

    runner.start(g1)
    runner.start(g2)
    await asyncio.sleep(0)

    assert set(refiner.calls) == {g1, g2}  # different gyms never coalesce

    refiner.gate.set()
    await _await_background()


@pytest.mark.asyncio
async def test_refine_failure_never_propagates() -> None:
    _reset_runner()

    class _BoomRefiner:
        async def refine_from_feed(self, gym_id):  # noqa: ANN001, ANN201
            raise RuntimeError("llm down")

    runner = VideoFeedRefineRunner(_BoomRefiner())
    gym = uuid4()

    runner.start(gym)  # must not raise into the (curation) caller
    await _await_background()

    # in-flight cleared even on failure, so a later curation can fire again.
    assert gym not in VideoFeedRefineRunner._in_flight_gyms


@pytest.mark.asyncio
async def test_drain_cancels_in_flight_and_clears() -> None:
    _reset_runner()
    refiner = _GatedRefiner()  # never completes on its own
    runner = VideoFeedRefineRunner(refiner)
    gym = uuid4()

    runner.start(gym)
    await asyncio.sleep(0)
    assert len(VideoFeedRefineRunner._background_runs) == 1

    await VideoFeedRefineRunner.drain()

    assert VideoFeedRefineRunner._background_runs == set()
    assert VideoFeedRefineRunner._in_flight_gyms == set()


# ── router wiring: which curations fire the runner ───────────────


def _auth() -> MagicMock:
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee = AsyncMock(return_value=None)
    return auth


@pytest.mark.asyncio
async def test_reject_fires_refine_runner() -> None:
    auth = _auth()
    svc = MagicMock()
    svc.remove_feed_video = AsyncMock(return_value=None)
    runner = MagicMock()
    gym = uuid4()

    await remove_gym_video(
        gym_id=gym,
        video_id="vid00000001",
        credentials=MagicMock(),
        owner=False,
        body=None,
        auth=auth,
        videos_service=svc,
        refine_runner=runner,
    )

    runner.start.assert_called_once_with(gym)


@pytest.mark.asyncio
async def test_owner_remove_does_not_fire_refine_runner() -> None:
    auth = _auth()
    svc = MagicMock()
    svc.remove_feed_video = AsyncMock(return_value=None)
    runner = MagicMock()

    await remove_gym_video(
        gym_id=uuid4(),
        video_id="vid00000001",
        credentials=MagicMock(),
        owner=True,
        body=None,
        auth=auth,
        videos_service=svc,
        refine_runner=runner,
    )

    runner.start.assert_not_called()


@pytest.mark.asyncio
async def test_keep_fires_refine_runner() -> None:
    auth = _auth()
    svc = MagicMock()
    svc.keep_feed_video = AsyncMock(return_value=None)
    runner = MagicMock()
    gym = uuid4()

    await keep_gym_video(
        gym_id=gym,
        video_id="vid00000001",
        credentials=MagicMock(),
        body=None,
        auth=auth,
        videos_service=svc,
        refine_runner=runner,
    )

    runner.start.assert_called_once_with(gym)


@pytest.mark.asyncio
async def test_owner_add_spawns_no_refine() -> None:
    # owner-add has no runner wired at all — calling it spawns no refine task.
    _reset_runner()
    auth = _auth()
    svc = MagicMock()
    svc.add_feed_video = AsyncMock(return_value=MagicMock())

    await add_gym_video(
        gym_id=uuid4(),
        body=MagicMock(url="https://youtu.be/abcdefghijk"),
        credentials=MagicMock(),
        auth=auth,
        videos_service=svc,
    )

    assert VideoFeedRefineRunner._background_runs == set()
