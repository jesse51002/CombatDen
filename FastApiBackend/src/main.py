from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.classes_router import classes_router
from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.discounts.discounts_router import discounts_router
from src.gyms.gyms_router import gyms_router
from src.members.members_router import members_router
from src.memberships.memberships_router import (
    member_memberships_router,
)
from src.memberships.service.memberships_invoice_fetch_runner import (
    MembershipsInvoiceFetchRunner,
)
from src.plans.plans_router import (
    membership_plans_router,
)
from src.ranks.ranks_router import ranks_router
from src.reconciler.reconciler_scheduler import build_scheduler
from src.rewards.rewards_router import rewards_router
from src.shared.paying_member_lock import LockBusyError
from src.stripe_webhooks.stripe_webhooks_router import stripe_webhooks_router
from src.tasks.tasks_router import tasks_router
from src.waivers.waivers_router import waivers_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    """Manage application startup and shutdown."""
    # The twice-daily reconciler sweep also recovers stale tasks (re-runs
    # unfinished tasks whose in-process execution died) as one of its steps.
    scheduler = None
    if settings.reconciler_enabled:
        scheduler = build_scheduler(app.container)
    if scheduler is not None:
        scheduler.start()
    try:
        yield
    finally:
        if scheduler is not None:
            scheduler.shutdown(wait=False)
        # Cancel + await any in-flight on-demand invoice fetches so the loop
        # isn't torn down mid-fetch with the DB pool already disposed.
        await MembershipsInvoiceFetchRunner.drain()
        await app.container.db_pool().engine.dispose()


async def _handle_lock_busy_error(
    request: Request,
    exc: LockBusyError,
) -> JSONResponse:
    """Map a busy payer lock to 409 Conflict (the documented contract).

    ``LockBusyError`` is raised when another billing op already holds the
    payer's lease. The contract (``settings.lock_acquire_timeout_seconds``)
    is 409 so the caller retries; without this handler it would surface as an
    unhandled 500. 409 is NOT in the proxy auto-retry family, so a mutating
    billing op is never silently replayed.
    """
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detail": str(exc)},
    )


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

    application.add_exception_handler(
        LockBusyError, _handle_lock_busy_error
    )

    application.include_router(classes_router)
    application.include_router(gyms_router)
    application.include_router(members_router)
    application.include_router(ranks_router)
    application.include_router(rewards_router)
    application.include_router(waivers_router)

    # === CRM billing routers (restored) ===
    # The payments package is a pure service core (no router); it is
    # injected by the billing domains rather than mounted directly.
    application.include_router(discounts_router)
    application.include_router(member_memberships_router)
    application.include_router(membership_plans_router)
    application.include_router(stripe_webhooks_router)
    # === end CRM billing routers ===

    # Tracked background operations (read-only polling endpoints).
    application.include_router(tasks_router)

    return application


app = create_app()


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "ok"}
