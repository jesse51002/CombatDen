"""Tests for the generic ``ResourceLock`` TTL-lease lock (real local DB).

Exercises the primitive in isolation against the ``resource_locks`` table:
acquire/release, contention (block then ``LockBusyError``), expiry-steal,
token-fenced release, independent keys, and the multi-key ``guard_many`` (acquire
all / release all / partial-failure release / no deadlock on the same pair). The
timing constants are monkeypatched small so the tests run fast.

Requires a migrated local DB (the ``resource_locks`` table).
"""

import asyncio
from uuid import uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.shared.resource_lock import LockBusyError, ResourceLock

MODULE = "src.shared.resource_lock"


async def _force_delete(db_pool, *keys: str) -> None:
    """Remove lock rows regardless of token (test cleanup)."""
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM resource_locks WHERE lock_key = ANY(:keys)"),
            {"keys": list(keys)},
        )
        await session.commit()


@pytest.fixture
def lock(db_pool) -> ResourceLock:
    return ResourceLock(db_pool)


@pytest.fixture
def fast_acquire(monkeypatch) -> None:
    """A short acquire budget so contention tests fail quickly."""
    monkeypatch.setattr(f"{MODULE}.LOCK_ACQUIRE_TIMEOUT_SECONDS", 0.5)
    monkeypatch.setattr(f"{MODULE}.LOCK_POLL_INTERVAL_SECONDS", 0.05)


async def test_guard_acquires_then_releases(lock, db_pool) -> None:
    key = f"test:{uuid4()}"
    try:
        async with lock.guard(key):
            # Held: a fresh token can't steal a live lease.
            assert await lock._try_acquire(key, uuid4()) is False
        # Released: the key is free again.
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)


async def test_second_acquire_blocks_then_raises(lock, db_pool, fast_acquire) -> None:
    key = f"test:{uuid4()}"
    try:
        async with lock.guard(key):
            with pytest.raises(LockBusyError) as exc:
                async with lock.guard(key):
                    pass
            assert exc.value.lock_key == key
    finally:
        await _force_delete(db_pool, key)


async def test_expired_lease_is_reacquirable(lock, db_pool, monkeypatch) -> None:
    monkeypatch.setattr(f"{MODULE}.LOCK_TTL_SECONDS", 1)
    key = f"test:{uuid4()}"
    try:
        # Acquire without releasing (simulate a crashed holder).
        assert await lock._try_acquire(key, uuid4()) is True
        await asyncio.sleep(1.2)  # let the 1s lease expire
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)


async def test_release_with_stale_token_is_noop(lock, db_pool) -> None:
    key = f"test:{uuid4()}"
    holder = uuid4()
    try:
        assert await lock._try_acquire(key, holder) is True
        # A release with the wrong token must NOT free the lease.
        await lock._release(key, uuid4())
        assert await lock._try_acquire(key, uuid4()) is False
        await lock._release(key, holder)
        # Now genuinely free.
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)


async def test_different_keys_acquire_independently(lock, db_pool) -> None:
    key_a, key_b = f"test:{uuid4()}", f"test:{uuid4()}"
    try:
        # A different key is unaffected — both acquire immediately.
        async with lock.guard(key_a), lock.guard(key_b):
            assert await lock._try_acquire(key_a, uuid4()) is False
            assert await lock._try_acquire(key_b, uuid4()) is False
    finally:
        await _force_delete(db_pool, key_a, key_b)


async def test_guard_many_acquires_all_then_releases_all(lock, db_pool) -> None:
    key_a, key_b = f"test:{uuid4()}", f"test:{uuid4()}"
    try:
        async with lock.guard_many([key_a, key_b]):
            assert await lock._try_acquire(key_a, uuid4()) is False
            assert await lock._try_acquire(key_b, uuid4()) is False
        # Both released on exit.
        for key in (key_a, key_b):
            token = uuid4()
            assert await lock._try_acquire(key, token) is True
            await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key_a, key_b)


async def test_guard_many_partial_failure_releases_taken(
    lock, db_pool, fast_acquire
) -> None:
    key_a, key_b = sorted([f"test:{uuid4()}", f"test:{uuid4()}"])
    held_by_other = uuid4()
    try:
        # Pre-hold the second key so guard_many gets key_a but not key_b.
        assert await lock._try_acquire(key_b, held_by_other) is True
        with pytest.raises(LockBusyError):
            async with lock.guard_many([key_a, key_b]):
                pass
        # key_a (taken first) must have been released on the failure.
        token = uuid4()
        assert await lock._try_acquire(key_a, token) is True
        await lock._release(key_a, token)
    finally:
        await _force_delete(db_pool, key_a, key_b)


async def test_guard_many_same_pair_does_not_deadlock(lock, db_pool) -> None:
    key_a, key_b = f"test:{uuid4()}", f"test:{uuid4()}"

    async def hold_pair() -> None:
        async with lock.guard_many([key_a, key_b]):
            await asyncio.sleep(0.1)

    try:
        # Sorted acquisition => the two never deadlock; both complete.
        await asyncio.wait_for(
            asyncio.gather(hold_pair(), hold_pair()),
            timeout=10,
        )
    finally:
        await _force_delete(db_pool, key_a, key_b)


async def test_max_hold_aborts_and_releases(lock, db_pool, monkeypatch) -> None:
    monkeypatch.setattr(f"{MODULE}.LOCK_MAX_HOLD_SECONDS", 0.3)
    key = f"test:{uuid4()}"
    try:
        with pytest.raises(TimeoutError):
            async with lock.guard(key):
                await asyncio.sleep(2)  # exceeds the 0.3s max hold
        # The lease was released when the block was aborted.
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)
