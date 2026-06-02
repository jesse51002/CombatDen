"""The read-only endpoints (single-tenant), all keyed by ``gym_id``: the gym
browser, one gym's full content detail, and one gym's paginated video feed. The
gym is the entry point — browse gyms, pick one, then load its detail (classes /
rewards / feed spec, read into memory once) and page through its video feed. The
``theme`` a gym carries is used only for branding, never to fetch content."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query, status

from schema import (
    BigGroup,
    FeedPreview,
    FeedSection,
    GymDetail,
    GymsPage,
    VideosFeed,
    VideoType,
)
from schema.big_group import big_group_for
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.avatar_fallback import card_with_avatar, instructor_avatars
from src.api.service.videos_service import videos_service

logger = logging.getLogger(__name__)

videos_router = APIRouter(tags=["videos"])

# Page size when the client doesn't ask: mobile-feed friendly, capped so one
# request can't pull everything.
DEFAULT_LIMIT = 20
MAX_LIMIT = 100
# Videos per genre in the one-shot "All" preview.
PREVIEW_PER_TAG = 10


@videos_router.get(
    "/gyms",
    response_model=GymsPage,
    summary="Get a page of gyms (the gym browser)",
    responses={
        200: {
            "description": (
                "A page of slim gym cards. Each carries the theme to brand with "
                "when picked + its celebration image; `total` is the gym count "
                "before pagination. `query` filters on gym id / theme / discipline"
            )
        },
        422: {"description": "A gym config is invalid, or bad limit/offset"},
    },
)
async def get_gyms(
    query: str | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
) -> GymsPage:
    """Return one page of gyms — the entry point. Pick a gym, then fetch its
    detail (`/gyms/{gym_id}`) and feed (`/gyms/{gym_id}/videos`). `query` is an
    optional substring filter; paginate with `limit`/`offset`."""
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
    "/gyms/{gym_id}",
    response_model=GymDetail,
    summary="Get one gym's full content detail (classes, rewards, feed spec)",
    responses={
        200: {
            "description": (
                "The gym's feed specification, branded class cards, and points-"
                "store reward cards, served verbatim — everything a member-app "
                "surface renders except the paginated video feed. The client "
                "reads this whole object into memory on selection"
            )
        },
        404: {"description": "No such gym"},
        422: {"description": "The gym config is invalid"},
    },
)
async def get_gym(gym_id: str) -> GymDetail:
    """Return one gym's full detail by ``gym_id`` — its spec, classes, and
    rewards. The video feed is separate (`/gyms/{gym_id}/videos`) because it
    pages."""
    try:
        gym = await videos_service().load_gym(gym_id)
        return GymDetail.from_gym(gym)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load gym detail for %s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym detail",
        ) from None


@videos_router.get(
    "/gyms/{gym_id}/videos",
    response_model=VideosFeed,
    summary="Get a page of a gym's video feed (approved, or rejected)",
    responses={
        200: {
            "description": (
                "A page of the gym's feed, hydrated from the shared pool in feed "
                "order: the scan-approved `good_video_ids` by default, or the "
                "scan's `rejected_video_ids` when `rejected=true`. "
                "`video_type`/`big_group` filter as expected"
            )
        },
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        404: {"description": "No such gym"},
        422: {"description": "A pooled video is stale, or bad limit/offset"},
    },
)
async def get_gym_videos(
    gym_id: str,
    video_type: VideoType | None = None,
    big_group: BigGroup | None = None,
    rejected: bool = Query(False),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
) -> VideosFeed:
    """Return one page of the gym's feed, hydrated from the shared pool in feed
    order. By default it serves **only that gym's ``good_video_ids``** (the
    scan's approved feed); ``rejected=true`` serves its ``rejected_video_ids``
    instead — the one place the rejected list is exposed read-only, so the admin
    can review and keep videos back. The raw pool is never served."""
    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )
    try:
        service = videos_service()
        gym = await service.load_gym(gym_id)
        # Read ONLY this gym's own ids from its row (load_gym), preserving feed
        # order — never the whole pool, so the feed costs O(feed size), not
        # O(pool size). `rejected` swaps the approved feed for the scan's
        # rejected list.
        ids = (
            gym.videos.rejected_video_ids
            if rejected
            else gym.videos.good_video_ids
        )
        videos = await service.load_videos(ids)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to load gym videos for %s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym videos",
        ) from None

    if video_type is not None:
        videos = [v for v in videos if v.tag == video_type]
    elif big_group is not None:
        videos = [
            v for v in videos if v.tag is not None and big_group_for(v.tag) == big_group
        ]

    total = len(videos)
    page = videos[offset : offset + limit]
    # Backfill empty channel avatars from the gym's instructor headshots (the
    # scraped pool has none). Built only for the page slice, so no extra cost.
    avatars = instructor_avatars(gym)
    cards = [card_with_avatar(v, avatars) for v in page]
    return VideosFeed(total=total, limit=limit, offset=offset, videos=cards)


@videos_router.get(
    "/gyms/{gym_id}/videos/preview",
    response_model=FeedPreview,
    summary="Get the 'All' preview: a few videos per genre in one request",
    responses={
        200: {
            "description": (
                "One section per genre present in the gym's feed, each capped to "
                "`per_tag` videos in feed order. Each genre is sampled "
                "individually, so none is starved by pagination. `rejected=true` "
                "previews the rejected list."
            )
        },
        404: {"description": "No such gym"},
        422: {"description": "A pooled video is stale"},
    },
)
async def get_gym_videos_preview(
    gym_id: str,
    rejected: bool = Query(False),
    per_tag: int = Query(PREVIEW_PER_TAG, ge=1, le=MAX_LIMIT),
) -> FeedPreview:
    """Power the "All" view in one request: hydrate the gym's feed once, group it
    by genre tag in feed order, and return up to ``per_tag`` videos per genre.
    Sampling each genre individually means no genre is dropped by global
    pagination. ``rejected=true`` previews the scan's rejected list instead."""
    try:
        service = videos_service()
        gym = await service.load_gym(gym_id)
        ids = (
            gym.videos.rejected_video_ids
            if rejected
            else gym.videos.good_video_ids
        )
        videos = await service.load_videos(ids)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to build feed preview for %s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build feed preview",
        ) from None

    # Group by the single genre tag, preserving first-appearance (feed) order,
    # and cap each genre to `per_tag`. Untagged videos form no section.
    order: list[VideoType] = []
    by_tag: dict[VideoType, list] = {}
    for v in videos:
        if v.tag is None:
            continue
        if v.tag not in by_tag:
            by_tag[v.tag] = []
            order.append(v.tag)
        if len(by_tag[v.tag]) < per_tag:
            by_tag[v.tag].append(v)
    # Backfill empty channel avatars from the gym's instructor headshots, as in
    # the paginated feed — the scraped pool carries none.
    avatars = instructor_avatars(gym)
    sections = [
        FeedSection(tag=t, videos=[card_with_avatar(v, avatars) for v in by_tag[t]])
        for t in order
    ]
    return FeedPreview(sections=sections)
