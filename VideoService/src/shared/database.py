"""Direct async Postgres connection pool over SQLAlchemy.

Modelled on ``FastApiBackend/src/shared/database.py`` — VideoService reads
from (and its scripts write to) the shared Supabase Postgres instead of flat
YAML. The background worker holds one process-scoped pool; the sync/import
scripts build their own. ``database_url`` is a ``postgresql+asyncpg://`` URL
from ``.env``.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from src.shared.config import settings

logger = logging.getLogger(__name__)

MAX_RETRIES = 3
BACKOFF_DELAYS = (0.5, 1.0, 2.0)


def to_asyncpg_url(url: str) -> str:
    """Coerce a Postgres URL onto the asyncpg driver the async engine needs.

    Supabase / standard connection strings are ``postgres://`` or
    ``postgresql://`` (which SQLAlchemy maps to the psycopg2 *sync* driver), but we
    use ``create_async_engine``, so they must be ``postgresql+asyncpg://``. A URL
    that already names a driver (``postgresql+<driver>://``) is left untouched.
    Lets ``.env`` / ``.env.prod`` hold a raw pasted Supabase URL.
    """
    if url.startswith("postgresql+"):
        return url
    if url.startswith("postgresql://"):
        return "postgresql+asyncpg://" + url[len("postgresql://"):]
    if url.startswith("postgres://"):
        return "postgresql+asyncpg://" + url[len("postgres://"):]
    return url


class DirectDatabasePool:
    """A direct async Postgres connection pool via SQLAlchemy."""

    def __init__(self, database_url: str | None = None) -> None:
        # `database_url` lets the write scripts target a different DB (e.g. prod,
        # loaded from .env.prod) without disturbing the API's global `settings`.
        self.engine = create_async_engine(
            to_asyncpg_url(database_url or settings.database_url),
            echo=settings.db_echo,
            pool_pre_ping=True,
            pool_size=settings.db_pool_size,
            max_overflow=settings.db_max_overflow,
        )
        self._session_factory = async_sessionmaker(
            self.engine,
            class_=AsyncSession,
            expire_on_commit=False,
        )

    @asynccontextmanager
    async def session(self) -> AsyncGenerator[AsyncSession]:
        """Yield an async database session, closing it after use."""
        async with self._session_factory() as session:
            yield session

    async def execute_with_retry(
        self,
        sql: str,
        params: dict[str, Any] | list[dict[str, Any]],
        max_retries: int = MAX_RETRIES,
    ) -> dict | None:
        """Execute a write query with retry + exponential backoff.

        Opens a session, executes, commits, and returns the first RETURNING row
        as a dict (or None). ``params`` may be a list for an executemany insert,
        in which case no row is returned.
        """
        last_exc: Exception | None = None
        for attempt in range(max_retries):
            try:
                async with self.session() as session:
                    result = await session.execute(text(sql), params)
                    row = (
                        result.mappings().fetchone()
                        if not isinstance(params, list) and result.returns_rows
                        else None
                    )
                    await session.commit()
                    return dict(row) if row else None
            except Exception as exc:  # noqa: BLE001 - retried then re-raised
                last_exc = exc
                if attempt < max_retries - 1:
                    delay = BACKOFF_DELAYS[min(attempt, len(BACKOFF_DELAYS) - 1)]
                    logger.warning("DB retry %d/%d: %s", attempt + 1, max_retries, exc)
                    await asyncio.sleep(delay)
        logger.error("All %d DB retries exhausted", max_retries, exc_info=True)
        raise last_exc  # type: ignore[misc]

    async def fetch_all(
        self,
        sql: str,
        params: dict[str, Any] | None = None,
    ) -> list[dict]:
        """Run a read query and return every row as a dict.

        ``execute_with_retry`` returns only the first RETURNING row, so
        multi-row SELECTs (the worker's funnel / enrich / scan reads) use this
        instead. Read-only: no commit.
        """
        async with self.session() as session:
            result = await session.execute(text(sql), params or {})
            return [dict(row) for row in result.mappings().all()]

    async def fetch_one(
        self,
        sql: str,
        params: dict[str, Any] | None = None,
    ) -> dict | None:
        """Run a read query and return the first row as a dict (or None)."""
        async with self.session() as session:
            result = await session.execute(text(sql), params or {})
            row = result.mappings().fetchone()
            return dict(row) if row else None

    async def dispose(self) -> None:
        """Dispose the engine's connection pool (call on shutdown)."""
        await self.engine.dispose()
