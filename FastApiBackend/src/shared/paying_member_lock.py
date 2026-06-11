"""The single concurrency-lock service for billing.

One class owns all locking. It locks a member's whole **paying-parent family**:
resolve any family member to the paying parent, then hold a TTL lease (a row in
``resource_locks``) on that parent's key, so no two billing ops touch the same
family at once. The payment-sync engine and the lifecycle callers depend on this
service rather than owning any lock mechanics themselves.

One public method — ``lock(member_ids)`` — an async context manager (so the lease
is always released on exit, even on exception, the max-hold timeout, or
cancellation). Pass a single member in a list; pass several (e.g. link/unlink
moving a member between paying parents) and all their families lock together.
Acquire takes a lease only when it is free or expired; a per-acquire token fences
release so a holder never deletes a lease another op re-took after theirs expired;
the max-hold (< the lease TTL) aborts a stuck op before its lease can expire, so a
concurrent op can never grab a still-running lease — the TTL is pure crash
recovery.
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
    PAYING_MEMBER_LOCK_PREFIX,
)
from src.shared.database import DirectDatabasePool
from src.shared.payer_resolver import PayerResolver
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


class LockBusyError(Exception):
    """A family's lease is held by another operation and could not be acquired."""

    def __init__(self, lock_key: str) -> None:
        self.lock_key = lock_key
        super().__init__(
            f"Lock '{lock_key}' is held by another operation",
        )


class PayingMemberLock:
    """The one concurrency lock, keyed on a member's resolved paying parent."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        parent_resolver: PayerResolver,
    ) -> None:
        self._db_pool = db_pool
        self._parent = parent_resolver

    @asynccontextmanager
    async def lock(self, member_ids: list[UUID]) -> AsyncGenerator[None]:
        """Hold the lease(s) for the families of all ``member_ids``.

        Wrap a single member in a list; pass several to lock several families at
        once. Resolves each member to its paying parent, dedupes + **sorts** the
        keys (so two ops requesting the same set never deadlock), acquires them all
        (blocking up to ``LOCK_ACQUIRE_TIMEOUT_SECONDS``, else ``LockBusyError``),
        holds under ``LOCK_MAX_HOLD_SECONDS``, and releases everything on exit.
        """
        keys = await self._resolve_keys(member_ids)
        token = uuid4()
        held: list[str] = []
        loop = asyncio.get_running_loop()
        deadline = loop.time() + LOCK_ACQUIRE_TIMEOUT_SECONDS
        try:
            for key in keys:
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

    async def _resolve_keys(self, member_ids: list[UUID]) -> list[str]:
        """Resolve each member to its paying-parent key; dedupe + sort."""
        keys: set[str] = set()
        for member_id in member_ids:
            parent = await self._parent.resolve_parent(member_id)
            keys.add(self._key(parent.member_id))
        return sorted(keys)

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
        """Release one key we hold; best-effort (the TTL recovers a missed one)."""
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

    @staticmethod
    def _key(parent_member_id: UUID) -> str:
        return f"{PAYING_MEMBER_LOCK_PREFIX}:{parent_member_id}"
