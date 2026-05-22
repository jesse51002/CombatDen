"""The read-only Videos Config API: `create_app()` plus the module-level `app`."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.config import settings
from src.api.videos_router import videos_router


def create_app() -> FastAPI:
    """Build the FastAPI app: CORS, the videos router, and a health probe."""
    application = FastAPI(
        title="CustomYoutubeService Videos Config API", version="0.1.0"
    )

    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET"],
        allow_headers=["*"],
    )

    application.include_router(videos_router)

    @application.get("/health", tags=["meta"])
    async def health_check() -> dict[str, str]:
        """Liveness probe."""
        return {"status": "ok"}

    return application


app = create_app()
