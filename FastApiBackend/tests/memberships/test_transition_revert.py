"""Regression test for C-085: transition revert must be atomic.

``_revert_db_phase`` previously ran THREE separate transactions
(delete-copied-discounts; delete-pending; uncancel-old), so a crash
mid-revert left a half-reverted membership. The fix wraps all three writes
in ONE transaction (a single session / single commit). This test proves the
revert opens exactly one session, issues all three writes on it, and commits
once — a pure unit test with a fake DB pool (no live DB / Stripe / network).
"""

import asyncio
from contextlib import asynccontextmanager
from unittest.mock import AsyncMock
from uuid import uuid4

from schema.member_membership import StripeSyncStatus

from src.memberships.service.memberships_transition_base import (
    MemberMembershipsTransitionBase,
)


class _FakeSession:
    """Records every ``execute`` and ``commit`` call."""

    def __init__(self) -> None:
        self.executed: list[str] = []
        self.commits: int = 0

    async def execute(self, statement, params=None):  # noqa: ANN001
        self.executed.append(str(statement))
        return None

    async def commit(self) -> None:
        self.commits += 1


class _FakePool:
    """Hands out fake sessions and counts how many were opened."""

    def __init__(self) -> None:
        self.sessions: list[_FakeSession] = []

    @asynccontextmanager
    async def session(self):  # noqa: ANN201
        sess = _FakeSession()
        self.sessions.append(sess)
        yield sess


def _make_service(pool: _FakePool) -> MemberMembershipsTransitionBase:
    svc = object.__new__(MemberMembershipsTransitionBase)
    svc._db_pool = pool  # type: ignore[attr-defined]
    # Successor not yet on Stripe -> revert proceeds (not the skip branch).
    svc._get_sync_status = AsyncMock(  # type: ignore[attr-defined]
        return_value=StripeSyncStatus.not_added
    )
    return svc


def test_revert_runs_in_one_transaction() -> None:
    pool = _FakePool()
    svc = _make_service(pool)

    asyncio.run(
        svc._revert_db_phase(
            member_id=uuid4(),
            old_item_id=uuid4(),
            new_item_id=uuid4(),
        )
    )

    # Exactly ONE session opened for all three writes (atomic revert).
    assert len(pool.sessions) == 1, (
        "revert must use a single shared transaction, not one per write"
    )
    sess = pool.sessions[0]
    # All three writes ran on that one session.
    assert len(sess.executed) == 3, (
        "expected delete-discounts + delete-pending + uncancel writes"
    )
    # Exactly one commit -> all-or-nothing.
    assert sess.commits == 1


def test_revert_skipped_when_successor_already_applied() -> None:
    pool = _FakePool()
    svc = _make_service(pool)
    svc._get_sync_status = AsyncMock(  # type: ignore[attr-defined]
        return_value=StripeSyncStatus.applied
    )

    asyncio.run(
        svc._revert_db_phase(
            member_id=uuid4(),
            old_item_id=uuid4(),
            new_item_id=uuid4(),
        )
    )

    # Known-residual guard: no session opened, nothing written.
    assert pool.sessions == []
