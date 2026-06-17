"""The single concurrency-lock service for billing.

One class owns all locking. It locks **payers**: hold a TTL lease (a row in
``resource_locks``) keyed on each passed member id — callers pass the PAYER
id(s) the op touches (a membership row's ``paid_by_member_id``, a start
request's payer, link/unlink's two accounts) — so no two billing ops converge
the same payer's subscription at once. There is no resolution step: the ids
passed ARE the keys. The payment-sync engine and the lifecycle callers depend
on this service rather than owning any lock mechanics themselves.

One public method — ``lock(member_ids)`` — an async context manager (so the lease
is always released on exit, even on exception, the max-hold timeout, or
cancellation). Pass a single payer in a list; pass several (e.g. link/unlink's
two accounts, or a start locking the payer plus the covered members) and they
all lock together. Acquire takes a lease only when it is free or expired; a
per-acquire token fences release so a holder never deletes a lease another op
re-took after theirs expired; the max-hold (< the lease TTL) aborts a stuck op
before its lease can expire, so a concurrent op can never grab a still-running
lease — the TTL is pure crash recovery.
"""

import asyncio
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


class LockBusyError(Exception):
    """A payer's lease is held by another operation and could not be acquired."""

    def __init__(self, lock_key: str) -> None:
        self.lock_key = lock_key
        super().__init__(
            f"Lock '{lock_key}' is held by another operation",
        )


class PayingMemberLock:
    """The one concurrency lock, keyed directly on the passed payer ids."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    @asynccontextmanager
    async def lock(self, member_ids: list[UUID]) -> AsyncGenerator[None]:
        """Hold the lease(s) for all ``member_ids`` (the keys, no resolution).

        Wrap a single payer in a list; pass several to lock several at once.
        Dedupes + **sorts** the keys (so two ops requesting the same set never
        deadlock), acquires them all (blocking up to
        ``settings.lock_acquire_timeout_seconds``, else ``LockBusyError``),
        holds under ``settings.lock_max_hold_seconds``, and releases everything
        on exit.
        """
        keys = self._keys(member_ids)
        token = uuid4()
        held: list[str] = []
        loop = asyncio.get_running_loop()
        deadline = loop.time() + settings.lock_acquire_timeout_seconds
        try:
            for key in keys:
                while not await self._try_acquire(key, token):
                    if loop.time() >= deadline:
                        raise LockBusyError(key)
                    await asyncio.sleep(settings.lock_poll_interval_seconds)
                held.append(key)
            async with asyncio.timeout(settings.lock_max_hold_seconds):
                yield
        finally:
            for key in held:
                await self._release(key, token)

    @classmethod
    def _keys(cls, member_ids: list[UUID]) -> list[str]:
        """The lock keys for the passed ids; dedupe + sort."""
        return sorted({cls._key(member_id) for member_id in member_ids})

    async def _try_acquire(self, key: str, token: UUID) -> bool:
        """Take the lease for one key; True iff acquired."""
        sql = load_sql(SQL_DIR / "acquire_resource_lock.sql")
        row = await self._db_pool.execute_with_retry(
            sql,
            {
                "lock_key": key,
                "token": str(token),
                "ttl_seconds": settings.lock_ttl_seconds,
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
    def _key(member_id: UUID) -> str:
        return f"{settings.paying_member_lock_prefix}:{member_id}"
