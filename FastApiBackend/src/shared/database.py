import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Any

from postgrest import AsyncPostgrestClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from src.core.config import settings

logger = logging.getLogger(__name__)

MAX_RETRIES = 3
BACKOFF_DELAYS = (0.5, 1.0, 2.0)


class DirectDatabasePool:
    """Manages a direct async Postgres connection pool via SQLAlchemy."""

    def __init__(self) -> None:
        self.engine = create_async_engine(
            settings.database_url,
            echo=settings.app_debug,
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
        params: dict[str, Any],
        max_retries: int = MAX_RETRIES,
    ) -> dict | None:
        """Execute a write query with retry and exponential backoff.

        Opens a session, executes the query, commits, and returns
        the first RETURNING row as a dict (or None if no rows).

        Args:
            sql: The SQL query string.
            params: Bind parameters for the query.
            max_retries: Maximum number of attempts (default 3).

        Returns:
            The first row as a dict if the query has RETURNING,
            otherwise None.

        Raises:
            Exception: The last exception if all retries exhausted.
        """
        last_exc: Exception | None = None

        for attempt in range(max_retries):
            try:
                async with self.session() as session:
                    result = await session.execute(text(sql), params)
                    row = result.mappings().fetchone()
                    await session.commit()
                    return dict(row) if row else None
            except Exception as exc:
                last_exc = exc
                if attempt < max_retries - 1:
                    delay = BACKOFF_DELAYS[min(attempt, len(BACKOFF_DELAYS) - 1)]
                    logger.warning(
                        "DB retry %d/%d: %s",
                        attempt + 1,
                        max_retries,
                        exc,
                    )
                    await asyncio.sleep(delay)

        logger.error(
            "All %d DB retries exhausted",
            max_retries,
            exc_info=True,
        )
        raise last_exc  # type: ignore[misc]


class SupabaseClient:
    """Manages the Supabase PostgREST client."""

    def __init__(self) -> None:
        self.client = AsyncPostgrestClient(
            base_url=f"{settings.supabase_url}/rest/v1",
            headers={
                "apikey": settings.supabase_service_role_key,
                "Authorization": (f"Bearer {settings.supabase_service_role_key}"),
            },
        )
