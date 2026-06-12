"""Tests for the ``PayingMemberLock`` TTL-lease lock (real local DB).

Exercises the one lock service against the ``resource_locks`` table: acquire /
release, contention (block then ``LockBusyError``), expiry-steal, token-fenced
release, independent families, and the multi-member ``lock`` (acquire all / dedupe
/ no deadlock on the same pair / max-hold abort). The resolver is mocked so each
member resolves to itself as the paying parent; the timing constants are
monkeypatched small so the tests run fast.

Requires a migrated local DB (the ``resource_locks`` table).
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.shared.paying_member_lock import LockBusyError, PayingMemberLock


async def _force_delete(db_pool, *keys: str) -> None:
    """Remove lock rows regardless of token (test cleanup)."""
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM resource_locks WHERE lock_key = ANY(:keys)"),
            {"keys": list(keys)},
        )
        await session.commit()


def _resolver() -> MagicMock:
    """A resolver where each member resolves to itself as the paying parent."""
    resolver = MagicMock()

    async def _resolve(member_id: UUID) -> MagicMock:
        parent = MagicMock()
        parent.member_id = member_id
        return parent

    resolver.resolve_parent = AsyncMock(side_effect=_resolve)
    return resolver


@pytest.fixture
def lock(db_pool) -> PayingMemberLock:
    return PayingMemberLock(db_pool, _resolver())


@pytest.fixture
def fast_acquire(monkeypatch) -> None:
    """A short acquire budget so contention tests fail quickly."""
    monkeypatch.setattr(settings, "lock_acquire_timeout_seconds", 0.5)
    monkeypatch.setattr(settings, "lock_poll_interval_seconds", 0.05)


async def test_lock_acquires_then_releases(lock, db_pool) -> None:
    m = uuid4()
    key = PayingMemberLock._key(m)
    try:
        async with lock.lock([m]):
            # Held: a fresh token can't steal a live lease.
            assert await lock._try_acquire(key, uuid4()) is False
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)


async def test_second_lock_blocks_then_raises(lock, db_pool, fast_acquire) -> None:
    m = uuid4()
    key = PayingMemberLock._key(m)
    try:
        async with lock.lock([m]):
            with pytest.raises(LockBusyError):
                async with lock.lock([m]):
                    pass
    finally:
        await _force_delete(db_pool, key)


async def test_expired_lease_is_reacquirable(lock, db_pool, monkeypatch) -> None:
    monkeypatch.setattr(settings, "lock_ttl_seconds", 1)
    key = PayingMemberLock._key(uuid4())
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
    key = PayingMemberLock._key(uuid4())
    holder = uuid4()
    try:
        assert await lock._try_acquire(key, holder) is True
        # A release with the wrong token must NOT free the lease.
        await lock._release(key, uuid4())
        assert await lock._try_acquire(key, uuid4()) is False
        await lock._release(key, holder)
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)


async def test_different_families_independent(lock, db_pool) -> None:
    a, b = uuid4(), uuid4()
    ka, kb = PayingMemberLock._key(a), PayingMemberLock._key(b)
    try:
        # Different families are unaffected — both acquire immediately.
        async with lock.lock([a]), lock.lock([b]):
            assert await lock._try_acquire(ka, uuid4()) is False
            assert await lock._try_acquire(kb, uuid4()) is False
    finally:
        await _force_delete(db_pool, ka, kb)


async def test_lock_acquires_all_and_dedupes(lock, db_pool) -> None:
    a, b = uuid4(), uuid4()
    ka, kb = PayingMemberLock._key(a), PayingMemberLock._key(b)
    try:
        # A duplicate member dedupes to one key; two distinct lock together.
        async with lock.lock([a, a, b]):
            assert await lock._try_acquire(ka, uuid4()) is False
            assert await lock._try_acquire(kb, uuid4()) is False
        for key in (ka, kb):
            token = uuid4()
            assert await lock._try_acquire(key, token) is True
            await lock._release(key, token)
    finally:
        await _force_delete(db_pool, ka, kb)


async def test_same_pair_does_not_deadlock(lock, db_pool) -> None:
    a, b = uuid4(), uuid4()
    ka, kb = PayingMemberLock._key(a), PayingMemberLock._key(b)

    async def hold_pair() -> None:
        async with lock.lock([a, b]):
            await asyncio.sleep(0.1)

    try:
        # Sorted acquisition => the two never deadlock; both complete.
        await asyncio.wait_for(
            asyncio.gather(hold_pair(), hold_pair()),
            timeout=10,
        )
    finally:
        await _force_delete(db_pool, ka, kb)


async def test_max_hold_aborts_and_releases(lock, db_pool, monkeypatch) -> None:
    monkeypatch.setattr(settings, "lock_max_hold_seconds", 0.3)
    m = uuid4()
    key = PayingMemberLock._key(m)
    try:
        with pytest.raises(TimeoutError):
            async with lock.lock([m]):
                await asyncio.sleep(2)  # exceeds the 0.3s max hold
        token = uuid4()
        assert await lock._try_acquire(key, token) is True
        await lock._release(key, token)
    finally:
        await _force_delete(db_pool, key)
