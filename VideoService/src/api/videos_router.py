"""The read-only endpoints: list companies, one company's full brief, its
search list, its fetched videos (optionally filtered by video type), and its
class cards."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query, status

from schema import (
    BigGroup,
    ClassOutput,
    VideoSearch,
    VideosConfig,
    VideosFeed,
    VideoType,
)
from schema.big_group import big_group_for
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import videos_service

logger = logging.getLogger(__name__)

videos_router = APIRouter(prefix="/apps", tags=["videos"])

# Page size when the client doesn't ask: mobile-feed friendly, capped so one
# request can't pull the whole feed.
DEFAULT_LIMIT = 20
MAX_LIMIT = 100


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
    summary="Get a company's search prompts",
    responses={
        200: {"description": "The company's search prompts"},
        404: {"description": "No such company"},
        422: {"description": "Brief exists but its videos_config.yaml is stale"},
    },
)
async def get_searches(app_id: str) -> list[VideoSearch]:
    """Return a company's searches. Searches are query-only — genre is decided
    per-video by the classification pass, so there is no video_type filter
    here (use ``/videos?video_type=`` for that)."""
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

    return config.searches


@videos_router.get(
    "/{app_id}/videos",
    response_model=VideosFeed,
    summary="Get a page of a company's fetched videos, optionally filtered",
    responses={
        200: {
            "description": (
                "A page of the company's video feed (slim, frontend-only "
                "fields), excluding off-niche videos (classifier "
                "`is_good == False`); `total` is the match count before "
                "pagination. `video_type` filters to one genre tag, `big_group` "
                "to the coarse educational/entertainment split"
            )
        },
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        404: {"description": "No such company, or it has no videos_output.yaml yet"},
        422: {"description": "Output is stale, or bad limit/offset"},
    },
)
async def get_videos(
    app_id: str,
    video_type: VideoType | None = None,
    big_group: BigGroup | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
) -> VideosFeed:
    """Return one page of a company's fetched videos, **excluding off-niche
    ones** (the classifier's ``is_good == False``); unclassified videos still
    serve. Filter with **either** ``?video_type=<genre>`` (one tag) **or**
    ``?big_group=<educational|entertainment>`` (the coarse split) — supplying
    both is a 400. Paginate with ``?limit=`` (default 20, max 100) and
    ``?offset=``; ``total`` reports how many videos matched before slicing."""
    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )
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

    # Off-niche videos (the classifier's `is_good == False`) are never served —
    # the verdict is enforced here, not on the client. Unclassified videos
    # (`is_good is None`, i.e. classify hasn't run) still serve, so a freshly
    # fetched feed isn't empty.
    videos = [v for v in output.videos if v.is_good is not False]
    if video_type is not None:
        videos = [v for v in videos if v.tag == video_type]
    elif big_group is not None:
        # A genre filter excludes unclassified videos (tag is None -> no group).
        videos = [
            v for v in videos if v.tag is not None and big_group_for(v.tag) == big_group
        ]

    total = len(videos)
    page = videos[offset : offset + limit]
    # VideoOutput -> VideoCard projection (drops desc/likes/transcript/
    # source_queries) via from_attributes on the slim models.
    return VideosFeed(
        company_name=output.company_name,
        app_id=output.app_id,
        generated_at=output.generated_at,
        total=total,
        limit=limit,
        offset=offset,
        videos=page,
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
