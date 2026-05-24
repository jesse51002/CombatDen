"""The read-only endpoints: list companies, one company's full brief, and its
search list (optionally filtered by video type)."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, status

from schema import ClassOutput, VideoSearch, VideosConfig, VideosFeed, VideoType
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import videos_service

logger = logging.getLogger(__name__)

videos_router = APIRouter(prefix="/apps", tags=["videos"])


@videos_router.get(
    "",
    response_model=list[str],
    summary="List companies that have a videos_config.yaml",
    responses={200: {"description": "Company ids, sorted"}},
)
async def list_apps() -> list[str]:
    """Return every company id with a brief on disk."""
    try:
        return await videos_service().list_apps()
    except Exception:
        logger.error("Failed to list companies", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list companies",
        ) from None


@videos_router.get(
    "/{app_id}",
    response_model=VideosConfig,
    summary="Get a company's full video-discovery brief",
    responses={
        200: {"description": "The company's validated videos_config.yaml"},
        404: {"description": "No such company"},
        422: {"description": "Brief exists but its videos_config.yaml is stale"},
    },
)
async def get_config(app_id: str) -> VideosConfig:
    """Return one company's full ``videos_config.yaml``."""
    try:
        return await videos_service().load(app_id)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load brief for %s", app_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load brief",
        ) from None


@videos_router.get(
    "/{app_id}/searches",
    response_model=list[VideoSearch],
    summary="Get a company's search prompts, optionally filtered by video type",
    responses={
        200: {
            "description": (
                "The company's search prompts; when `video_type` is given, "
                "only searches whose `tags` include it"
            )
        },
        404: {"description": "No such company"},
        422: {"description": "Brief exists but its videos_config.yaml is stale"},
    },
)
async def get_searches(
    app_id: str, video_type: VideoType | None = None
) -> list[VideoSearch]:
    """Return a company's searches. With ``?video_type=<enum>``, return only
    searches tagged with that genre."""
    try:
        config = await videos_service().load(app_id)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load searches for %s", app_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load searches",
        ) from None

    if video_type is None:
        return config.searches
    return [s for s in config.searches if video_type in s.tags]


@videos_router.get(
    "/{app_id}/videos",
    response_model=VideosFeed,
    summary="Get a company's fetched videos, optionally filtered by video type",
    responses={
        200: {
            "description": (
                "The company's video feed (slim, frontend-only fields); when "
                "`video_type` is given, only videos whose `tags` include it"
            )
        },
        404: {"description": "No such company, or it has no videos_output.yaml yet"},
        422: {"description": "Output exists but its videos_output.yaml is stale"},
    },
)
async def get_videos(
    app_id: str, video_type: VideoType | None = None
) -> VideosFeed:
    """Return a company's fetched videos. With ``?video_type=<enum>``, return
    only videos tagged with that genre."""
    try:
        output = await videos_service().load_output(app_id)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load videos for %s", app_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load videos",
        ) from None

    videos = output.videos
    if video_type is not None:
        videos = [v for v in videos if video_type in v.tags]
    # VideoOutput -> VideoCard projection (drops desc/likes/source_queries) via
    # from_attributes on the slim models.
    return VideosFeed(
        company_name=output.company_name,
        app_id=output.app_id,
        generated_at=output.generated_at,
        videos=videos,
    )


@videos_router.get(
    "/{app_id}/classes",
    response_model=ClassOutput,
    summary="Get a company's four branded class cards",
    responses={
        200: {"description": "The company's class_output.yaml (4 name + image cards)"},
        404: {"description": "No such company, or it has no class_output.yaml yet"},
        422: {"description": "Classes exist but the class_output.yaml is stale"},
    },
)
async def get_classes(app_id: str) -> ClassOutput:
    """Return a company's four branded class cards (name + horizontal image)."""
    try:
        return await videos_service().load_classes(app_id)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load classes for %s", app_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load classes",
        ) from None
