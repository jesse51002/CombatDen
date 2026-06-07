"""Generic distributed lock: a TTL-lease row keyed on an arbitrary string.

Reusable, service-role-only mutual exclusion backed by the ``resource_locks``
table. Acquire takes the row only when it is free or its lease has expired; a
per-acquire token fences release so a holder never deletes a lease another op
re-took after theirs expired.

The only public interface is the ``guard`` / ``guard_many`` async context
managers, so a lease is **always** released by ``__aexit__`` (the ``finally``)
even on exception, the max-hold timeout, or task cancellation. The payment-sync
engine holds a lease across a multi-transaction Stripe sequence; the hard max-hold
(< the lease TTL) aborts a stuck op before its lease can expire, so a concurrent
op can never grab a still-running lease — the TTL is pure crash recovery.
"""

import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID, uuid4

from src.core.config import (
    LOCK_ACQUIRE_TIMEOUT_SECONDS,
    LOCK_MAX_HOLD_SECONDS,
    LOCK_POLL_INTERVAL_SECONDS,
    LOCK_TTL_SECONDS,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


class LockBusyError(Exception):
    """A resource lock is held by another operation and could not be acquired."""

    def __init__(self, lock_key: str) -> None:
        self.lock_key = lock_key
        super().__init__(
            f"Resource lock '{lock_key}' is held by another operation",
        )


class ResourceLock:
    """A generic TTL-lease distributed lock over the ``resource_locks`` table."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    @asynccontextmanager
    async def guard(self, key: str) -> AsyncGenerator[None]:
        """Hold a single lock for the duration of the block."""
        async with self.guard_many([key]):
            yield

    @asynccontextmanager
    async def guard_many(self, keys: list[str]) -> AsyncGenerator[None]:
        """Hold one or more locks for the duration of the block.

        Keys are deduped and acquired in **sorted** order, so two ops requesting
        the same set never deadlock. Acquisition blocks up to
        ``LOCK_ACQUIRE_TIMEOUT_SECONDS`` (one shared budget); on timeout it
        releases anything already taken and raises ``LockBusyError``. The block is
        bounded by ``LOCK_MAX_HOLD_SECONDS`` (< the lease TTL) and every held lease
        is released on exit.
        """
        ordered = sorted(set(keys))
        token = uuid4()
        held: list[str] = []
        loop = asyncio.get_running_loop()
        deadline = loop.time() + LOCK_ACQUIRE_TIMEOUT_SECONDS
        try:
            for key in ordered:
                while not await self._try_acquire(key, token):
                    if loop.time() >= deadline:
                        raise LockBusyError(key)
                    await asyncio.sleep(LOCK_POLL_INTERVAL_SECONDS)
                held.append(key)
            async with asyncio.timeout(LOCK_MAX_HOLD_SECONDS):
                yield
        finally:
            for key in held:
                await self._release(key, token)

    async def _try_acquire(self, key: str, token: UUID) -> bool:
        """Take the lease for one key; True iff acquired."""
        sql = load_sql(SQL_DIR / "acquire_resource_lock.sql")
        row = await self._db_pool.execute_with_retry(
            sql,
            {
                "lock_key": key,
                "token": str(token),
                "ttl_seconds": LOCK_TTL_SECONDS,
            },
        )
        return row is not None

    async def _release(self, key: str, token: UUID) -> None:
        """Release one key we hold; best-effort (the TTL recovers a missed release)."""
        sql = load_sql(SQL_DIR / "release_resource_lock.sql")
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {"lock_key": key, "token": str(token)},
            )
        except Exception:
            logger.error(
                "Failed to release resource lock '%s'",
                key,
                exc_info=True,
            )
