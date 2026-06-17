"""A generic TTL-lease lock over the ``resource_locks`` table.

This is the low-level, key-agnostic counterpart to ``PayingMemberLock``: it owns
no key-naming policy and resolves nothing — callers pass a fully-formed
``lock_key`` string and get a single-shot, **non-blocking** acquire (the row is
taken only when free or its lease has expired). It exists so non-family callers
(the scheduled reconciler's global sweep lock, the orphan-cleanup family check)
can reuse the exact same atomic acquire/release SQL without inheriting
``PayingMemberLock``'s blocking-poll + paying-parent-key contract.

Acquire takes a lease only when it is free or expired; a per-acquire token fences
release so a holder never deletes a lease another op re-took after theirs expired.
The TTL is pure crash recovery — a single-shot holder releases promptly in its
``finally``.

``PayingMemberLock`` is intentionally left on its own copy of the mechanics for
now (it guards the critical billing path); both write the same table with
compatible keys, so a ``try_lock`` here correctly contends with a blocking
``PayingMemberLock.lock`` on the same key.
"""

import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID, uuid4

from src.core.config import settings
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


class ResourceLock:
    """A generic, non-blocking TTL-lease lock keyed by an arbitrary string."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def acquire_once(
        self,
        key: str,
        token: UUID,
        ttl_seconds: int | None = None,
    ) -> bool:
        """Try once to take the lease for ``key``; True iff acquired.

        Non-blocking: a single atomic ``INSERT ... ON CONFLICT`` that succeeds
        only when the lease is free or expired. Returns ``False`` immediately
        when another operation holds a live lease. ``ttl_seconds`` defaults to
        ``settings.lock_ttl_seconds``.
        """
        if ttl_seconds is None:
            ttl_seconds = settings.lock_ttl_seconds
        sql = load_sql(SQL_DIR / "acquire_resource_lock.sql")
        row = await self._db_pool.execute_with_retry(
            sql,
            {
                "lock_key": key,
                "token": str(token),
                "ttl_seconds": ttl_seconds,
            },
        )
        return row is not None

    async def release(self, key: str, token: UUID) -> None:
        """Release ``key`` if we still hold it; best-effort (TTL recovers)."""
        sql = load_sql(SQL_DIR / "release_resource_lock.sql")
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {"lock_key": key, "token": str(token)},
            )
        except Exception:
            logger.error(
                "Failed to release lock '%s'",
                key,
                exc_info=True,
            )

    @asynccontextmanager
    async def try_lock(
        self,
        key: str,
        ttl_seconds: int | None = None,
    ) -> AsyncGenerator[bool]:
        """Single-shot non-blocking lock as a context manager.

        Mints its own token and yields ``True`` when the lease was taken
        (released on exit), or ``False`` when another op holds it (a no-op on
        exit — nothing was acquired, so nothing is released).

        Usage::

            async with resource_lock.try_lock(key) as got:
                if not got:
                    return  # held elsewhere; skip
                ...  # do the guarded work
        """
        token = uuid4()
        acquired = await self.acquire_once(key, token, ttl_seconds)
        try:
            yield acquired
        finally:
            if acquired:
                await self.release(key, token)
