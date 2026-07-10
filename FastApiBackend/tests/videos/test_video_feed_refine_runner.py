"""Feed-learning refine runner + the router wiring that fires it.

Pure unit tests (no DB / network):

* ``VideoFeedRefineRunner`` — ``start`` fires a detached refine; per-gym
  COALESCED with a dirty flag (a ``start`` for an in-flight gym is dropped but
  marks it dirty, so exactly ONE follow-up refine runs when the in-flight one
  finishes — the mid-flight signal is coalesced, never lost); the guard clears
  when the refine finishes so a later curation fires afresh; a refine failure
  never propagates; ``drain`` cancels + clears in-flight/dirty work.
* The router wiring — a manual REJECT (``remove_gym_video`` ``owner=False``) and a
  KEEP (``keep_gym_video``) fire the runner ONLY when the service reports the
  write actually curated a row (a no-op reject/keep does NOT); an owner-section
  remove (``owner=True``) does NOT; owner-add spawns no refine at all.
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
    """Clear the ClassVar-backed task + in-flight + dirty sets between tests."""
    VideoFeedRefineRunner._background_runs.clear()
    VideoFeedRefineRunner._in_flight_gyms.clear()
    VideoFeedRefineRunner._dirty_gyms.clear()


async def _await_background() -> None:
    """Await every in-flight refine task to completion (without cancelling)."""
    runs = list(VideoFeedRefineRunner._background_runs)
    for run in runs:
        await asyncio.gather(run, return_exceptions=True)


async def _drain_until_idle() -> None:
    """Await tasks repeatedly until none remain — a coalesced follow-up refine is
    scheduled as a NEW task while its predecessor finishes, so one gather pass
    isn't enough to reach quiescence."""
    for _ in range(100):
        runs = list(VideoFeedRefineRunner._background_runs)
        if not runs:
            return
        await asyncio.gather(*runs, return_exceptions=True)
    raise AssertionError("runner never became idle")


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
async def test_start_coalesces_and_reruns_once_for_mid_flight_signal() -> None:
    # The lost-signal path: a curation arriving WHILE a refine is in flight is
    # dropped by the in-flight guard, but marks the gym dirty so exactly ONE
    # follow-up refine runs when the in-flight one finishes — the mid-flight
    # signal is coalesced, never lost, and a burst is never one-refine-per-drop.
    _reset_runner()
    refiner = _GatedRefiner()
    runner = VideoFeedRefineRunner(refiner)
    gym = uuid4()

    runner.start(gym)
    runner.start(gym)  # mid-flight → dropped-but-marks-dirty (NOT lost)
    runner.start(gym)  # mid-flight → still just dirty (coalesced)
    await asyncio.sleep(0)  # let the one scheduled task reach its gate

    assert refiner.calls == [gym]  # only one refine in flight so far
    assert len(VideoFeedRefineRunner._background_runs) == 1
    assert gym in VideoFeedRefineRunner._dirty_gyms

    refiner.gate.set()  # let the in-flight refine (and its follow-up) finish
    await _drain_until_idle()

    # Exactly ONE follow-up refine ran for the mid-flight signal — two total, not
    # five (one per dropped start) and not one (the last signal dropped forever).
    assert refiner.calls == [gym, gym]
    assert VideoFeedRefineRunner._in_flight_gyms == set()
    assert VideoFeedRefineRunner._dirty_gyms == set()


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
    # A reject that actually curated a served row → the service returns True.
    svc.remove_feed_video = AsyncMock(return_value=True)
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
async def test_reject_noop_does_not_fire_refine_runner() -> None:
    # A no-op reject (video not in the served run, or already rejected) → the
    # service returns False → no wasted refine (which could also consume a
    # genuinely-pending signal).
    auth = _auth()
    svc = MagicMock()
    svc.remove_feed_video = AsyncMock(return_value=False)
    runner = MagicMock()

    await remove_gym_video(
        gym_id=uuid4(),
        video_id="vid00000001",
        credentials=MagicMock(),
        owner=False,
        body=None,
        auth=auth,
        videos_service=svc,
        refine_runner=runner,
    )

    runner.start.assert_not_called()


@pytest.mark.asyncio
async def test_owner_remove_does_not_fire_refine_runner() -> None:
    auth = _auth()
    svc = MagicMock()
    # An owner-section delete is never a curation signal → the service returns
    # False, and the router also gates owner-removes out regardless.
    svc.remove_feed_video = AsyncMock(return_value=False)
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
    # A keep that actually un-rejected a served row → the service returns True.
    svc.keep_feed_video = AsyncMock(return_value=True)
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
async def test_keep_noop_does_not_fire_refine_runner() -> None:
    # Keeping an already-accepted video (or one not in the served run) curates 0
    # rows → the service returns False → no wasted refine.
    auth = _auth()
    svc = MagicMock()
    svc.keep_feed_video = AsyncMock(return_value=False)
    runner = MagicMock()

    await keep_gym_video(
        gym_id=uuid4(),
        video_id="vid00000001",
        credentials=MagicMock(),
        body=None,
        auth=auth,
        videos_service=svc,
        refine_runner=runner,
    )

    runner.start.assert_not_called()


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
