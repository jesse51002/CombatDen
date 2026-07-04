"""Unit tests: OrphanCleanupSweep deletes an orphan's applied-discount
children before its own item row, in one transaction.

A stranded ``not_added`` membership item may carry ``not_added`` applied-
discount snapshot children; the FK ``fk_applied_discount_membership_gym``
(``member_membership_applied_discounts_unfiltered`` -> ``member_memberships_unfiltered``)
blocks the item's DELETE unless the children go first. These tests mock
``db_pool`` / ``resource_lock`` entirely so no DB is touched — the real-DB
coverage (an actual FK-blocked row cleaned up end to end against the shared
local Supabase DB) lives in ``tests/reconciler/test_reconciler.py``.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from src.reconciler.service.reconciler.reconciler_orphan_cleanup_sweep import (
    OrphanCleanupSweep,
)
from src.reconciler.service.reconciler.reconciler_result import SweepResult


def _mock_session() -> AsyncMock:
    """An AsyncMock usable as ``async with db_pool.session() as session``."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    return session


def _mock_db_pool(session: AsyncMock) -> MagicMock:
    pool = MagicMock()
    pool.session.return_value = session
    return pool


def _fake_lock(acquired: bool) -> MagicMock:
    """A ``ResourceLock`` double whose ``try_lock`` always yields ``acquired``."""

    @asynccontextmanager
    async def _try_lock(key: str, ttl_seconds: int | None = None):
        yield acquired

    lock = MagicMock()
    lock.try_lock = _try_lock
    return lock


# ── _delete_orphan: ordering + scoping ──────────────────────────


async def test_delete_orphan_deletes_discount_children_before_item() -> None:
    """The discount-child DELETE runs before the item DELETE, then one commit."""
    session = _mock_session()
    sweep = OrphanCleanupSweep(_mock_db_pool(session), _fake_lock(True))
    item_id = uuid4()

    await sweep._delete_orphan(item_id)

    assert session.execute.await_count == 2
    first_sql = str(session.execute.await_args_list[0].args[0])
    second_sql = str(session.execute.await_args_list[1].args[0])
    assert "member_membership_applied_discounts_unfiltered" in first_sql
    assert "member_memberships_unfiltered" in second_sql
    session.commit.assert_awaited_once()


async def test_delete_orphan_scopes_both_deletes_to_the_item_id() -> None:
    """Both deletes are bound to this orphan's item_id only."""
    session = _mock_session()
    sweep = OrphanCleanupSweep(_mock_db_pool(session), _fake_lock(True))
    item_id = uuid4()

    await sweep._delete_orphan(item_id)

    discount_params = session.execute.await_args_list[0].args[1]
    item_params = session.execute.await_args_list[1].args[1]
    assert discount_params == {"item_id": str(item_id)}
    assert item_params == {"item_ids": [str(item_id)]}


# ── _try_cleanup_one: SweepResult semantics ─────────────────────


async def test_try_cleanup_one_deletes_and_counts_changed() -> None:
    """A free payer lock deletes the orphan and counts it as ``changed``."""
    session = _mock_session()
    sweep = OrphanCleanupSweep(_mock_db_pool(session), _fake_lock(True))
    result = SweepResult(name="orphan_cleanup")
    orphan = {"item_id": uuid4(), "paid_by_member_id": uuid4()}

    await sweep._try_cleanup_one(orphan, result)

    assert result.changed == 1
    assert result.skipped == 0
    session.commit.assert_awaited_once()


async def test_try_cleanup_one_skips_when_lock_held() -> None:
    """A held payer lock leaves the orphan untouched and counts as ``skipped``."""
    session = _mock_session()
    sweep = OrphanCleanupSweep(_mock_db_pool(session), _fake_lock(False))
    result = SweepResult(name="orphan_cleanup")
    orphan = {"item_id": uuid4(), "paid_by_member_id": uuid4()}

    await sweep._try_cleanup_one(orphan, result)

    assert result.skipped == 1
    assert result.changed == 0
    session.execute.assert_not_awaited()
