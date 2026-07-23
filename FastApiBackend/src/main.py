from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.checkin_router import checkin_router
from src.classes.classes_router import classes_router
from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.discounts.discounts_router import discounts_router
from src.employees.employees_router import employees_router
from src.growth.growth_router import growth_router
from src.growth.growth_scheduler import build_growth_scheduler
from src.gyms.gyms_router import gyms_router
from src.member_portal.member_portal_router import member_portal_router
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
from src.presets.presets_router import presets_router
from src.ranks.ranks_router import ranks_router
from src.reconciler.reconciler_scheduler import build_scheduler
from src.rewards.rewards_router import rewards_router
from src.shared.paying_member_lock import LockBusyError
from src.stripe_webhooks.stripe_webhooks_router import stripe_webhooks_router
from src.tasks.tasks_router import tasks_router
from src.theme.theme_router import theme_router
from src.uploads.uploads_router import uploads_router
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)
from src.videos.service.video_feed_refine_runner import (
    VideoFeedRefineRunner,
)
from src.videos.videos_router import videos_router
from src.waivers.waivers_router import waivers_router


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    """Manage application startup and shutdown."""
    # Identity is the verified email claim; that "verified" means anything
    # depends on GoTrue actually mailing confirmations. Check its published
    # config before serving a single request.
    await app.container.auth_settings_guard().check()

    scheduler = None
    if settings.reconciler_enabled:
        scheduler = build_scheduler(app.container)
    if scheduler is not None:
        scheduler.start()
    # Separate scheduler: the growth compute runs on its own interval (and
    # immediately at launch), independent of the reconciler's cron.
    growth_scheduler = None
    if settings.growth_enabled:
        growth_scheduler = build_growth_scheduler(app.container)
    if growth_scheduler is not None:
        growth_scheduler.start()
    try:
        yield
    finally:
        if scheduler is not None:
            scheduler.shutdown(wait=False)
        if growth_scheduler is not None:
            growth_scheduler.shutdown(wait=False)
        # Drain in-flight fetches before pool disposal.
        await MembershipsInvoiceFetchRunner.drain()
        await MemberVideoProfileRefreshRunner.drain()
        await VideoFeedRefineRunner.drain()
        await app.container.db_pool().engine.dispose()


async def _handle_lock_busy_error(
    request: Request,
    exc: LockBusyError,
) -> JSONResponse:
    """Map a busy payer lock to 409 Conflict (not in the proxy auto-retry family)."""
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

    application.include_router(checkin_router)
    application.include_router(classes_router)
    application.include_router(growth_router)
    application.include_router(gyms_router)
    application.include_router(members_router)
    application.include_router(ranks_router)
    application.include_router(rewards_router)
    application.include_router(waivers_router)
    application.include_router(employees_router)

    # The member-facing portal — every route gated by verify_member_self.
    # Staff routes above are unchanged and remain staff-only.
    application.include_router(member_portal_router)

    application.include_router(discounts_router)
    application.include_router(member_memberships_router)
    application.include_router(membership_plans_router)
    application.include_router(stripe_webhooks_router)

    application.include_router(tasks_router)

    # Uploads: multipart image proxy → S3 + CloudFront CDN.
    application.include_router(uploads_router)

    # Videos: a real gym's live feed + the LLM authoring surface for a gym's
    # append-only spec.
    application.include_router(videos_router)

    # Presets: transactional template import + public template catalog.
    application.include_router(presets_router)

    # Theme: gym showcase (branded class/reward cards).
    application.include_router(theme_router)

    return application


app = create_app()


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint."""
    return {"status": "ok"}
