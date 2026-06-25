"""API routes for the videos domain.

Two read-only surfaces (no prefix — each route declares its full path, since the
domain spans both ``/api/v1/videos`` and ``/api/v1/gyms``):

    * ``GET /api/v1/videos/templates``                  — page the slug-keyed
      template catalog (any authenticated user).
    * ``GET /api/v1/videos/templates/{video_gym_id}``   — one template's full
      detail (any authenticated user).
    * ``GET /api/v1/gyms/{gym_id}/videos``              — a real gym's paginated
      served feed.
    * ``GET /api/v1/gyms/{gym_id}/videos/preview``      — the one-shot "All"
      preview (a few videos per genre).
    * ``GET /api/v1/gyms/{gym_id}/videos/spec``         — the gym's live video
      spec.
    * ``GET /api/v1/gyms/{gym_id}/showcase``            — the gym's spec +
      branded class/reward cards.

The template surface is the catalog the preset import copies FROM; the gym
surface is a real customer gym's live content.
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from schema.video import VideoGenre

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.videos.schema.videos_big_group import BigGroup, big_group_for
from src.videos.schema.videos_schema import (
    GymFeedPreview,
    GymFeedSection,
    GymShowcase,
    GymVideosFeed,
    GymVideoSpecView,
    VideoTemplateCatalogPage,
    VideoTemplateDetail,
)
from src.videos.service.videos_avatar_fallback import (
    card_with_avatar,
    instructor_avatars,
)
from src.videos.service.videos_service import VideosService

logger = logging.getLogger(__name__)

videos_router = APIRouter(tags=["videos"])

# Page size when the client doesn't ask: mobile-feed friendly, capped so one
# request can't pull everything.
DEFAULT_LIMIT = 20
MAX_LIMIT = 100
# Videos per genre in the one-shot "All" preview.
PREVIEW_PER_TAG = 10


# ── Template catalog ──────────────────────────────────────────


# The template catalog is PUBLIC (anon-readable): it serves only the
# non-sensitive demo `video_gym` templates, and the unauthenticated public theme
# browser previews them. This mirrors VideoService's open read API, which these
# endpoints replace.


@videos_router.get(
    "/api/v1/videos/templates",
    response_model=VideoTemplateCatalogPage,
    summary="Page the video template catalog (public)",
    description=(
        "A page of slim template cards (the slug-keyed ``video_gym`` catalog "
        "the preset import copies from). Each carries its theme + celebration "
        "image; ``total`` is the template count before pagination. ``query`` "
        "filters on slug / theme / discipline. Public (no auth)."
    ),
    responses={
        200: {"description": "A page of template cards"},
    },
)
@inject
async def list_templates(
    query: str | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> VideoTemplateCatalogPage:
    """Return one page of the template catalog (public)."""
    try:
        return await videos_service.list_template_cards(
            limit=limit, offset=offset, query=query
        )
    except Exception:
        logger.error("Failed to list video templates", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list video templates",
        ) from None


@videos_router.get(
    "/api/v1/videos/templates/{video_gym_id}",
    response_model=VideoTemplateDetail,
    summary="Get one video template's full detail (spec, classes, rewards)",
    description=(
        "The template's feed specification, branded class cards, and points-"
        "store reward cards, served verbatim. Public (no auth)."
    ),
    responses={
        200: {"description": "The template detail"},
        404: {"description": "No such template"},
    },
)
@inject
async def get_template(
    video_gym_id: str,
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> VideoTemplateDetail:
    """Return one template's full detail by slug (public)."""
    try:
        detail = await videos_service.load_template(video_gym_id)
    except Exception:
        logger.error(
            "Failed to load video template %s", video_gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load video template",
        ) from None
    if detail is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No template {video_gym_id!r}",
        )
    return detail


def _template_avatars(detail: VideoTemplateDetail) -> list[str]:
    """The template's instructor headshots, deduped in first-seen order — the
    avatar-backfill pool for the template feed (the shared pool carries none)."""
    seen: dict[str, None] = {}
    for card in detail.classes or ():
        if card.instructor_image_url:
            seen.setdefault(card.instructor_image_url, None)
    return list(seen)


@videos_router.get(
    "/api/v1/videos/templates/{video_gym_id}/videos",
    response_model=GymVideosFeed,
    summary="Get a page of a template's video feed (public)",
    description=(
        "A page of the template's approved feed, hydrated from the shared pool "
        "in relevance order. ``video_type``/``big_group`` filter as expected "
        "(mutually exclusive). Public (no auth)."
    ),
    responses={
        200: {"description": "A page of the template's feed"},
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        404: {"description": "No such template"},
    },
)
@inject
async def get_template_videos(
    video_gym_id: str,
    video_type: VideoGenre | None = None,
    big_group: BigGroup | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideosFeed:
    """Return one page of a template's feed, hydrated from the shared pool."""
    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )
    try:
        detail = await videos_service.load_template(video_gym_id)
        if detail is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No template {video_gym_id!r}",
            )
        ids = await videos_service.load_template_feed_ids(video_gym_id)
        videos = await videos_service.load_pool_videos(ids)
    except HTTPException:
        raise
    except Exception:
        logger.error(
            "Failed to load template videos for %s", video_gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load template videos",
        ) from None

    if video_type is not None:
        videos = [v for v in videos if v.tag == video_type]
    elif big_group is not None:
        videos = [
            v
            for v in videos
            if v.tag is not None and big_group_for(v.tag) == big_group
        ]

    total = len(videos)
    page = videos[offset : offset + limit]
    avatars = _template_avatars(detail)
    cards = [card_with_avatar(v, avatars) for v in page]
    return GymVideosFeed(total=total, limit=limit, offset=offset, videos=cards)


@videos_router.get(
    "/api/v1/videos/templates/{video_gym_id}/videos/preview",
    response_model=GymFeedPreview,
    summary="Get a template's 'All' preview: a few videos per genre (public)",
    description=(
        "One section per genre present in the template's feed, each capped to "
        "``per_tag`` videos in feed order. Public (no auth)."
    ),
    responses={
        200: {"description": "One section per genre"},
        404: {"description": "No such template"},
    },
)
@inject
async def get_template_videos_preview(
    video_gym_id: str,
    per_tag: int = Query(PREVIEW_PER_TAG, ge=1, le=MAX_LIMIT),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymFeedPreview:
    """The template's "All" preview: its feed grouped by genre, capped per genre."""
    try:
        detail = await videos_service.load_template(video_gym_id)
        if detail is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No template {video_gym_id!r}",
            )
        ids = await videos_service.load_template_feed_ids(video_gym_id)
        videos = await videos_service.load_pool_videos(ids)
    except HTTPException:
        raise
    except Exception:
        logger.error(
            "Failed to build template preview for %s",
            video_gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build template preview",
        ) from None

    order: list[VideoGenre] = []
    by_tag: dict[VideoGenre, list] = {}
    for v in videos:
        if v.tag is None:
            continue
        if v.tag not in by_tag:
            by_tag[v.tag] = []
            order.append(v.tag)
        if len(by_tag[v.tag]) < per_tag:
            by_tag[v.tag].append(v)
    avatars = _template_avatars(detail)
    sections = [
        GymFeedSection(
            tag=t, videos=[card_with_avatar(v, avatars) for v in by_tag[t]]
        )
        for t in order
    ]
    return GymFeedPreview(sections=sections)


# ── A real gym's live feed ────────────────────────────────────
# NOTE: Phase 2 — when the member MobileApp repoints here, the
# feed/preview/spec/showcase guards must widen to allow gym MEMBERS, not only
# employees.


@videos_router.get(
    "/api/v1/gyms/{gym_id}/videos",
    response_model=GymVideosFeed,
    summary="Get a page of a gym's served video feed",
    description=(
        "A page of the gym's served feed, hydrated from the shared pool in "
        "relevance order. ``video_type``/``big_group`` filter as expected "
        "(mutually exclusive). Empty channel avatars are backfilled from the "
        "gym's instructor headshots."
    ),
    responses={
        200: {"description": "A page of the gym's feed"},
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def get_gym_videos(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    video_type: VideoGenre | None = None,
    big_group: BigGroup | None = None,
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideosFeed:
    """Return one page of the gym's served feed, hydrated from the shared pool in
    relevance order, with channel-avatar backfill."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )

    try:
        ids = await videos_service.load_feed_ids(gym_id)
        videos = await videos_service.load_pool_videos(ids)
        classes = await videos_service.load_showcase_classes(gym_id)
    except Exception:
        logger.error(
            "Failed to load gym videos for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym videos",
        ) from None

    if video_type is not None:
        videos = [v for v in videos if v.tag == video_type]
    elif big_group is not None:
        videos = [
            v
            for v in videos
            if v.tag is not None and big_group_for(v.tag) == big_group
        ]

    total = len(videos)
    page = videos[offset : offset + limit]
    # Backfill empty channel avatars from the gym's instructor headshots (the
    # scraped pool has none). Built only for the page slice, so no extra cost.
    avatars = instructor_avatars(classes)
    cards = [card_with_avatar(v, avatars) for v in page]
    return GymVideosFeed(total=total, limit=limit, offset=offset, videos=cards)


@videos_router.get(
    "/api/v1/gyms/{gym_id}/videos/preview",
    response_model=GymFeedPreview,
    summary="Get the 'All' preview: a few videos per genre in one request",
    description=(
        "One section per genre present in the gym's feed, each capped to "
        "``per_tag`` videos in feed order. Each genre is sampled individually, "
        "so none is starved by pagination."
    ),
    responses={
        200: {"description": "One section per genre"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def get_gym_videos_preview(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    per_tag: int = Query(PREVIEW_PER_TAG, ge=1, le=MAX_LIMIT),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymFeedPreview:
    """Power the "All" view in one request: hydrate the gym's feed once, group it
    by genre tag in feed order, and return up to ``per_tag`` videos per genre."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        ids = await videos_service.load_feed_ids(gym_id)
        videos = await videos_service.load_pool_videos(ids)
        classes = await videos_service.load_showcase_classes(gym_id)
    except Exception:
        logger.error(
            "Failed to build feed preview for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build feed preview",
        ) from None

    # Group by the single genre tag, preserving first-appearance (feed) order,
    # and cap each genre to `per_tag`. Untagged videos form no section.
    order: list[VideoGenre] = []
    by_tag: dict[VideoGenre, list] = {}
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
    avatars = instructor_avatars(classes)
    sections = [
        GymFeedSection(
            tag=t, videos=[card_with_avatar(v, avatars) for v in by_tag[t]]
        )
        for t in order
    ]
    return GymFeedPreview(sections=sections)


@videos_router.get(
    "/api/v1/gyms/{gym_id}/videos/spec",
    response_model=GymVideoSpecView,
    summary="Get a gym's live video spec",
    description=(
        "The gym's live video spec (its disciplines, the short display summary, "
        "the full scan criteria, and the preset-import provenance)."
    ),
    responses={
        200: {"description": "The gym's video spec"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
        404: {"description": "No spec authored for this gym"},
    },
)
@inject
async def get_gym_videos_spec(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideoSpecView:
    """Return the gym's live video spec, 404 when no spec row exists."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        spec = await videos_service.load_gym_spec(gym_id)
    except Exception:
        logger.error(
            "Failed to load gym video spec for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym video spec",
        ) from None
    if spec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No video spec for this gym",
        )
    return spec


@videos_router.get(
    "/api/v1/gyms/{gym_id}/showcase",
    response_model=GymShowcase,
    summary="Get a gym's showcase (spec + branded class/reward cards)",
    description=(
        "The gym's live video spec plus its branded class cards and points-store "
        "reward cards. ``spec`` may be None until authored; ``classes`` / "
        "``rewards`` are possibly-empty lists."
    ),
    responses={
        200: {"description": "The gym's showcase"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def get_gym_showcase(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymShowcase:
    """Return the gym's showcase: its spec (or None) + class/reward cards."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        spec = await videos_service.load_gym_spec(gym_id)
        classes = await videos_service.load_showcase_classes(gym_id)
        rewards = await videos_service.load_showcase_rewards(gym_id)
    except Exception:
        logger.error(
            "Failed to load gym showcase for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym showcase",
        ) from None
    return GymShowcase(
        gym_id=gym_id, spec=spec, classes=classes, rewards=rewards
    )
