"""The studio app: `create_app()` plus the module-level `app`.

Local only. `make studio` binds it to 127.0.0.1:8002 — it is a laptop tool
that spends real money on every launch, and nothing about it is deployed.
The read-only API in `src/api/` is the one that ships.
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.studio.brief_router import brief_router
from src.studio.config import settings
from src.studio.run_router import run_router


def create_app() -> FastAPI:
    """Build the studio app: CORS, the two routers, and a health probe."""
    application = FastAPI(title="ThemeService Studio", version="0.1.0")

    application.add_middleware(
        CORSMiddleware,
        # Explicit origins, not "*": this app STARTS PAID RUNS, so it is not
        # something any page should be able to POST to.
        allow_origins=settings.studio_cors_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["*"],
    )

    application.include_router(run_router)
    application.include_router(brief_router)

    @application.get("/health", tags=["meta"])
    async def health_check() -> dict[str, str]:
        """Liveness probe."""
        return {"status": "ok"}

    return application


app = create_app()
