from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.classes_router import classes_router
from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.discounts.discounts_router import discounts_router
from src.member_memberships.member_memberships_router import (
    member_memberships_router,
)
from src.members.members_router import members_router
from src.membership_plans.membership_plans_router import (
    membership_plans_router,
)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    """Manage application startup and shutdown."""
    yield
    await app.container.db_pool().engine.dispose()


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    container = DependencyInjector()

    application = FastAPI(
        title="CombatDen API",
        version="0.1.0",
        docs_url="/docs" if settings.app_debug else None,
        redoc_url="/redoc" if settings.app_debug else None,
        lifespan=lifespan,
    )

    application.container = container

    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    application.include_router(classes_router)
    application.include_router(discounts_router)
    application.include_router(members_router)
    application.include_router(member_memberships_router)
    application.include_router(membership_plans_router)

    return application


app = create_app()


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "ok"}
