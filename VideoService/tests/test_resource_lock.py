"""ResourceLock port + the new renew — pure, no DB.

Stubs the DB pool (records the ``(sql, params)`` each call makes) and asserts:

- ``acquire_once`` returns True/False on row-present/None and binds the right
  params, defaulting the TTL from settings;
- ``renew`` binds ``lock_key`` / ``token`` / ``ttl_seconds``, returns True/False
  on row-present/None, and its SQL is a token-fenced UPDATE ... RETURNING;
- ``release`` deletes by key+token and swallows a pool failure (best-effort);
- every lock ``.sql`` uses the functional ``CAST(:p AS TYPE)`` (never ``:p::type``).

Follows the suite's ``asyncio.run`` convention (no pytest-asyncio).
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from uuid import uuid4

from src.shared.config import settings
from src.shared.services import resource_lock as resource_lock_module
from src.shared.services.resource_lock import ResourceLock


class _FakePool:
    """Records every execute_with_retry call; returns a fixed row."""

    def __init__(self, row: dict | None) -> None:
        self._row = row
        self.calls: list[tuple[str, dict]] = []

    async def execute_with_retry(
        self, sql: str, params: dict, max_retries: int = 3
    ) -> dict | None:
        self.calls.append((sql, params))
        return self._row


class _BoomPool:
    async def execute_with_retry(
        self, sql: str, params: dict, max_retries: int = 3
    ) -> dict | None:
        raise RuntimeError("db down")


def test_acquire_once_true_and_binds() -> None:
    pool = _FakePool({"token": "abc"})
    lock = ResourceLock(pool)
    token = uuid4()

    got = asyncio.run(lock.acquire_once("k", token, ttl_seconds=30))

    assert got is True
    sql, params = pool.calls[0]
    assert "INSERT INTO resource_locks" in sql
    assert "ON CONFLICT" in sql
    assert "CAST(:token AS UUID)" in sql
    assert params == {"lock_key": "k", "token": str(token), "ttl_seconds": 30}


def test_acquire_once_false_when_no_row() -> None:
    lock = ResourceLock(_FakePool(None))
    got = asyncio.run(lock.acquire_once("k", uuid4(), ttl_seconds=30))
    assert got is False


def test_acquire_once_defaults_ttl_from_settings() -> None:
    pool = _FakePool(None)
    lock = ResourceLock(pool)
    asyncio.run(lock.acquire_once("k", uuid4()))
    _, params = pool.calls[0]
    assert params["ttl_seconds"] == settings.lock_ttl_seconds


def test_renew_true_and_binds() -> None:
    pool = _FakePool({"token": "abc"})
    lock = ResourceLock(pool)
    token = uuid4()

    ok = asyncio.run(lock.renew("k", token, ttl_seconds=45))

    assert ok is True
    sql, params = pool.calls[0]
    assert "UPDATE resource_locks" in sql
    assert "RETURNING token" in sql
    assert "CAST(:token AS UUID)" in sql
    assert params == {"lock_key": "k", "token": str(token), "ttl_seconds": 45}


def test_renew_false_when_row_gone() -> None:
    lock = ResourceLock(_FakePool(None))
    ok = asyncio.run(lock.renew("k", uuid4(), ttl_seconds=45))
    assert ok is False


def test_renew_defaults_ttl_from_settings() -> None:
    pool = _FakePool({"token": "abc"})
    lock = ResourceLock(pool)
    asyncio.run(lock.renew("k", uuid4()))
    _, params = pool.calls[0]
    assert params["ttl_seconds"] == settings.lock_ttl_seconds


def test_release_deletes_by_key_and_token() -> None:
    pool = _FakePool(None)
    lock = ResourceLock(pool)
    token = uuid4()

    asyncio.run(lock.release("k", token))

    sql, params = pool.calls[0]
    assert "DELETE FROM resource_locks" in sql
    assert "CAST(:token AS UUID)" in sql
    assert params == {"lock_key": "k", "token": str(token)}


def test_release_swallows_pool_error() -> None:
    lock = ResourceLock(_BoomPool())
    # best-effort: a pool failure must not propagate (TTL recovers the lease).
    asyncio.run(lock.release("k", uuid4()))


def test_lock_sql_uses_functional_cast_not_colon_colon() -> None:
    sql_dir = Path(resource_lock_module.__file__).parent / "sql"
    files = (
        "acquire_resource_lock.sql",
        "release_resource_lock.sql",
        "renew_resource_lock.sql",
    )
    for name in files:
        text = (sql_dir / name).read_text()
        # No bind param may be immediately followed by ``::`` (asyncpg breaks).
        for param in (":token", ":lock_key", ":ttl_seconds"):
            assert f"{param}::" not in text, f"{name}: {param}:: cast"
        assert "CAST(:token AS UUID)" in text
