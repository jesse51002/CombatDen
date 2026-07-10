"""Unit tests for the per-member-coalesced profile refresh runner.

Pure (no DB / network):

* ``MemberVideoProfileRefreshRunner`` — ``start`` fires a detached refresh;
  per-member COALESCED with a dirty flag (a ``start`` for an in-flight member is
  dropped but marks it dirty, so exactly ONE follow-up refresh runs when the
  in-flight one finishes — two concurrent first-signals spawn ONE paid build, not
  two, and no signal is lost); different members never coalesce; a FAILED build is
  logged at ERROR with the member id and never propagates to the caller; ``drain``
  cancels + clears in-flight/dirty work.
"""

from __future__ import annotations

import asyncio
import logging
from uuid import uuid4

import pytest

from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)


def _reset() -> None:
    MemberVideoProfileRefreshRunner._background_runs.clear()
    MemberVideoProfileRefreshRunner._in_flight_members.clear()
    MemberVideoProfileRefreshRunner._dirty_members.clear()


async def _drain_until_idle() -> None:
    """Await tasks repeatedly until none remain (a coalesced follow-up refresh is
    a NEW task scheduled while its predecessor finishes)."""
    for _ in range(100):
        runs = list(MemberVideoProfileRefreshRunner._background_runs)
        if not runs:
            return
        await asyncio.gather(*runs, return_exceptions=True)
    raise AssertionError("runner never became idle")


class _CountingProfiles:
    def __init__(self) -> None:
        self.calls: list[tuple] = []

    async def refresh_if_due(self, member_id, gym_id):  # noqa: ANN001, ANN201
        self.calls.append((member_id, gym_id))


class _GatedProfiles:
    def __init__(self) -> None:
        self.calls: list[tuple] = []
        self.gate = asyncio.Event()

    async def refresh_if_due(self, member_id, gym_id):  # noqa: ANN001, ANN201
        self.calls.append((member_id, gym_id))
        await self.gate.wait()


@pytest.mark.asyncio
async def test_start_fires_refresh() -> None:
    _reset()
    profiles = _CountingProfiles()
    runner = MemberVideoProfileRefreshRunner(profiles)
    member, gym = uuid4(), uuid4()

    runner.start(member, gym)
    await _drain_until_idle()

    assert profiles.calls == [(member, gym)]
    assert MemberVideoProfileRefreshRunner._in_flight_members == set()


@pytest.mark.asyncio
async def test_coalesces_and_reruns_once_for_mid_flight_signal() -> None:
    # Two concurrent first-signals (a click + a class sign-up) for one member: the
    # second is dropped-but-marks-dirty, so ONE build runs in flight and exactly
    # ONE follow-up — one paid build in flight at a time, and no dropped signal.
    _reset()
    profiles = _GatedProfiles()
    runner = MemberVideoProfileRefreshRunner(profiles)
    member, gym = uuid4(), uuid4()

    runner.start(member, gym)
    runner.start(member, gym)  # mid-flight → dropped-but-marks-dirty
    runner.start(member, gym)  # mid-flight → still just dirty
    await asyncio.sleep(0)

    assert profiles.calls == [(member, gym)]  # only one build in flight
    assert member in MemberVideoProfileRefreshRunner._dirty_members

    profiles.gate.set()
    await _drain_until_idle()

    assert profiles.calls == [(member, gym), (member, gym)]  # one follow-up
    assert MemberVideoProfileRefreshRunner._in_flight_members == set()
    assert MemberVideoProfileRefreshRunner._dirty_members == set()


@pytest.mark.asyncio
async def test_independent_across_members() -> None:
    _reset()
    profiles = _GatedProfiles()
    runner = MemberVideoProfileRefreshRunner(profiles)
    gym = uuid4()
    m1, m2 = uuid4(), uuid4()

    runner.start(m1, gym)
    runner.start(m2, gym)  # different member → not coalesced
    await asyncio.sleep(0)

    assert {c[0] for c in profiles.calls} == {m1, m2}

    profiles.gate.set()
    await _drain_until_idle()


@pytest.mark.asyncio
async def test_failed_build_is_logged_and_never_propagates(
    caplog: pytest.LogCaptureFixture,
) -> None:
    _reset()

    class _BoomProfiles:
        async def refresh_if_due(self, member_id, gym_id):  # noqa: ANN001, ANN201
            raise RuntimeError("summary model down")

    runner = MemberVideoProfileRefreshRunner(_BoomProfiles())
    member, gym = uuid4(), uuid4()

    with caplog.at_level(logging.ERROR):
        runner.start(member, gym)  # must not raise into the (click) caller
        await _drain_until_idle()

    # The failure is visible (ERROR + the member id) so a NULL embedding isn't
    # silent, and the guard cleared so a later signal can fire again.
    assert any(
        record.levelno == logging.ERROR and str(member) in record.getMessage()
        for record in caplog.records
    )
    assert member not in MemberVideoProfileRefreshRunner._in_flight_members


@pytest.mark.asyncio
async def test_drain_cancels_in_flight_and_clears() -> None:
    _reset()
    profiles = _GatedProfiles()  # never completes on its own
    runner = MemberVideoProfileRefreshRunner(profiles)
    member, gym = uuid4(), uuid4()

    runner.start(member, gym)
    await asyncio.sleep(0)
    assert len(MemberVideoProfileRefreshRunner._background_runs) == 1

    await MemberVideoProfileRefreshRunner.drain()

    assert MemberVideoProfileRefreshRunner._background_runs == set()
    assert MemberVideoProfileRefreshRunner._in_flight_members == set()
    assert MemberVideoProfileRefreshRunner._dirty_members == set()
