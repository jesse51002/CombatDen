"""A generic TTL-lease lock over the shared ``resource_locks`` table.

Ported from ``FastApiBackend/src/shared/resource_lock.py`` (imports rewritten
for this service) and extended with ``renew`` for long-running holders. The
table is the SAME shared ``resource_locks`` the backend uses — no schema change.

Callers pass a fully-formed ``lock_key`` string; this owns no key-naming policy.
``acquire_once`` is a single-shot, non-blocking acquire (the row is taken only
when free or its lease has expired). A per-acquire ``token`` fences ``release``
and ``renew`` so a holder never disturbs a lease another op re-took after theirs
expired. The TTL is crash recovery: a stuck holder self-heals once its lease
lapses — and a long-running worker takes a short TTL, then heartbeats via
``renew`` for as long as it holds the work.
"""

from __future__ import annotations

import logging
from pathlib import Path
from uuid import UUID

from src.api.config import settings
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
        """Try once to take the lease for ``key``; ``True`` iff acquired.

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

    async def renew(
        self,
        key: str,
        token: UUID,
        ttl_seconds: int | None = None,
    ) -> bool:
        """Extend our lease on ``key``; ``True`` iff we still held it.

        Heartbeat for a long-running holder: pushes ``expires_at`` out only
        while ``token`` still matches the row. Returns ``False`` when the row is
        gone or another operation re-took the lease after ours expired — the
        caller must then treat the lock as lost. ``ttl_seconds`` defaults to
        ``settings.lock_ttl_seconds``.
        """
        if ttl_seconds is None:
            ttl_seconds = settings.lock_ttl_seconds
        sql = load_sql(SQL_DIR / "renew_resource_lock.sql")
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
            logger.error("Failed to release lock '%s'", key, exc_info=True)
