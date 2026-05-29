"""The read-only endpoints (single-tenant): the gym browser, and per-theme
videos / classes / rewards. Gyms are the entry point — browse gyms, pick one,
then load the theme it carries and fetch that gym's videos/classes/rewards."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query, status

from schema import (
    BigGroup,
    GymsPage,
    ThemeClasses,
    ThemeRewards,
    VideosFeed,
    VideoType,
)
from schema.big_group import big_group_for
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import videos_service
from src.shared.util.video_id import video_id_from_url

logger = logging.getLogger(__name__)

videos_router = APIRouter(tags=["videos"])

# Page size when the client doesn't ask: mobile-feed friendly, capped so one
# request can't pull everything.
DEFAULT_LIMIT = 20
MAX_LIMIT = 100


@videos_router.get(
    "/gyms",
    response_model=GymsPage,
    summary="Get a page of gyms (the gym browser)",
    responses={
        200: {
            "description": (
                "A page of slim gym cards. Each carries the theme to load when "
                "picked + its celebration image; `total` is the gym count before "
                "pagination. `query` filters on gym id / theme / discipline"
            )
        },
        422: {"description": "A gym file is stale, or bad limit/offset"},
    },
)
async def get_gyms(
    query: str | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
) -> GymsPage:
    """Return one page of gyms — the entry point. Pick a gym, then load the
    **theme it carries** (`card.theme`) and fetch its videos/classes/rewards.
    `query` is an optional substring filter; paginate with `limit`/`offset`."""
    try:
        return await videos_service().list_gyms_page(
            limit=limit, offset=offset, query=query
        )
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to list gyms", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list gyms",
        ) from None


@videos_router.get(
    "/themes/{design_id}/videos",
    response_model=VideosFeed,
    summary="Get a page of the gym feed for a theme (design id)",
    responses={
        200: {
            "description": (
                "A page of the video feed for the theme's gym: only that gym's "
                "`good_video_ids` (the scan-approved feed), hydrated from the "
                "shared pool. `video_type`/`big_group` filter as expected"
            )
        },
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        404: {"description": "Theme not mapped to a gym"},
        422: {"description": "A pooled video is stale, or bad limit/offset"},
    },
)
async def get_theme_videos(
    design_id: str,
    video_type: VideoType | None = None,
    big_group: BigGroup | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
) -> VideosFeed:
    """Return one page of the feed for a **theme**. Resolves ``design_id`` to its
    gym, then serves **only that gym's ``good_video_ids``** (the scan's approved
    feed), hydrated from the shared pool in feed order. The raw pool and the
    gym's rejected list are never served."""
    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )
    try:
        service = videos_service()
        gym = await service.gym_for_theme(design_id)
        pool = await service.load_pool()
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load theme videos for %s", design_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load theme videos",
        ) from None

    # Hydrate the gym's approved feed from the pool, preserving good_video_ids
    # order. Ids not present in the pool are skipped.
    by_id = {video_id_from_url(v.url): v for v in pool}
    videos = [by_id[vid] for vid in gym.videos.good_video_ids if vid in by_id]
    if video_type is not None:
        videos = [v for v in videos if v.tag == video_type]
    elif big_group is not None:
        videos = [
            v for v in videos if v.tag is not None and big_group_for(v.tag) == big_group
        ]

    total = len(videos)
    page = videos[offset : offset + limit]
    return VideosFeed(total=total, limit=limit, offset=offset, videos=page)


@videos_router.get(
    "/themes/{design_id}/classes",
    response_model=ThemeClasses,
    summary="Get the branded class cards for a theme (design id)",
    responses={
        200: {"description": "The theme's gym's class cards"},
        404: {"description": "Theme not mapped to a gym, or the gym has no class cards"},
        422: {"description": "The gym file is stale"},
    },
)
async def get_theme_classes(design_id: str) -> ThemeClasses:
    """Return the branded class cards for a **theme** (which live on its gym)."""
    try:
        classes = await videos_service().classes_for_theme(design_id)
        return ThemeClasses(classes=classes)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load theme classes for %s", design_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load theme classes",
        ) from None


@videos_router.get(
    "/themes/{design_id}/rewards",
    response_model=ThemeRewards,
    summary="Get the points-store reward cards for a theme (design id)",
    responses={
        200: {"description": "The theme's gym's reward cards"},
        404: {"description": "Theme not mapped to a gym, or the gym has no reward cards"},
        422: {"description": "The gym file is stale"},
    },
)
async def get_theme_rewards(design_id: str) -> ThemeRewards:
    """Return the points-store reward cards for a **theme** (which live on its gym)."""
    try:
        rewards = await videos_service().rewards_for_theme(design_id)
        return ThemeRewards(rewards=rewards)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load theme rewards for %s", design_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load theme rewards",
        ) from None
