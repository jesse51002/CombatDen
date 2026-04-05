from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from postgrest import AsyncPostgrestClient
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from src.core.config import settings


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
