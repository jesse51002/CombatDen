"""API routes for the videos domain.

Two read-only surfaces (no prefix — each route declares its full path, since the
domain spans both ``/api/v1/videos`` and ``/api/v1/gyms``):

    * ``GET /api/v1/videos/templates``                  — page the slug-keyed
      template catalog (any authenticated user).
    * ``GET /api/v1/videos/templates/{video_gym_id}``   — one template's full
      detail (any authenticated user).
    * ``GET /api/v1/gyms/{gym_id}/videos``              — a real gym's paginated
      served feed.
    * ``POST /api/v1/gyms/{gym_id}/videos/lookup``      — fetch a YouTube link's
      real metadata (no write) for the add confirmation.
    * ``POST /api/v1/gyms/{gym_id}/videos``             — add one owner-provided
      YouTube link to the gym's feed (fetches its real metadata).
    * ``DELETE /api/v1/gyms/{gym_id}/videos/{video_id}`` — remove one video from
      the gym's feed (and log the removal + reason).
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
    GymVideoCard,
    GymVideosFeed,
    GymVideoSpecView,
    VideoAddRequest,
    VideoRemoveRequest,
    VideoTemplateCatalogPage,
    VideoTemplateDetail,
)
from src.videos.service.videos_avatar_fallback import (
    card_with_avatar,
    instructor_avatars,
)
from src.videos.service.videos_service import VideosService
from src.videos.service.youtube_metadata import (
    YouTubeApiError,
    YouTubeVideoNotFoundError,
)

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
    rejected: bool = Query(False),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideosFeed:
    """Return one page of a template's feed, hydrated from the shared pool.
    ``rejected=true`` serves the scan's rejected list (admin review)."""
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
        ids = await videos_service.load_template_feed_ids(
            video_gym_id, rejected=rejected
        )
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
    rejected: bool = Query(False),
    per_tag: int = Query(PREVIEW_PER_TAG, ge=1, le=MAX_LIMIT),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymFeedPreview:
    """The template's "All" preview: its feed grouped by genre, capped per genre.
    ``rejected=true`` previews the scan's rejected list."""
    try:
        detail = await videos_service.load_template(video_gym_id)
        if detail is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No template {video_gym_id!r}",
            )
        ids = await videos_service.load_template_feed_ids(
            video_gym_id, rejected=rejected
        )
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
    owner: bool = Query(False),
    rejected: bool = Query(False),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideosFeed:
    """Return one page of the gym's feed, hydrated from the shared pool in
    relevance order, with channel-avatar backfill. ``owner=true`` → the owner
    "Your videos" section (else the gym's latest scan run); ``rejected=true`` →
    the rejected list (else the served, accepted videos)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )

    try:
        ids = await videos_service.load_feed_ids(
            gym_id, owner=owner, rejected=rejected
        )
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


@videos_router.post(
    "/api/v1/gyms/{gym_id}/videos/lookup",
    response_model=GymVideoCard,
    summary="Look up a YouTube link's details (no write) for an add confirmation",
    description=(
        "Fetch a YouTube link's real metadata (title / channel / thumbnail / "
        "views / duration / channel avatar) from the YouTube Data API and return "
        "it as a card, WITHOUT adding it to the feed. Powers the 'confirm these "
        "details before adding' step; the owner then POSTs to add it."
    ),
    responses={
        200: {"description": "The looked-up video's card (nothing was written)"},
        400: {
            "description": "The URL is not a recognisable YouTube link, or no "
            "such video exists (private / deleted / invalid)"
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
        502: {"description": "The YouTube Data API could not be reached"},
    },
)
@inject
async def lookup_gym_video(
    gym_id: UUID,
    body: VideoAddRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideoCard:
    """Return a YouTube link's details for the add confirmation — no write."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        card = await videos_service.lookup_feed_video(body.url)
        classes = await videos_service.load_showcase_classes(gym_id)
    except (ValueError, YouTubeVideoNotFoundError) as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from None
    except YouTubeApiError:
        logger.error(
            "YouTube Data API failed looking up video for %s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not reach YouTube to fetch the video's details",
        ) from None
    except Exception:
        logger.error("Failed to look up gym video for %s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to look up video",
        ) from None

    avatars = instructor_avatars(classes)
    return card_with_avatar(card, avatars)


@videos_router.post(
    "/api/v1/gyms/{gym_id}/videos",
    response_model=GymVideoCard,
    summary="Add a single YouTube video to a gym's feed",
    description=(
        "Add one owner-provided YouTube link to the gym's served feed. The id is "
        "extracted from the URL and the video's real metadata (title / channel / "
        "thumbnail / views / duration / channel avatar) is fetched from the "
        "YouTube Data API and stored. Idempotent — re-adding a video already in "
        "the feed returns its card without duplicating it."
    ),
    responses={
        200: {"description": "The added video's card"},
        400: {
            "description": "The URL is not a recognisable YouTube link, or no "
            "such video exists (private / deleted / invalid)"
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
        502: {"description": "The YouTube Data API could not be reached"},
    },
)
@inject
async def add_gym_video(
    gym_id: UUID,
    body: VideoAddRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideoCard:
    """Add one YouTube video to the gym's feed (with real metadata fetched from
    the YouTube Data API) and return its card, with the same channel-avatar
    backfill the feed applies."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        card = await videos_service.add_feed_video(gym_id, body.url)
        classes = await videos_service.load_showcase_classes(gym_id)
    except (ValueError, YouTubeVideoNotFoundError) as exc:
        # Bad link or a video that doesn't exist — the owner's input is at fault.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from None
    except YouTubeApiError:
        logger.error(
            "YouTube Data API failed adding video for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not reach YouTube to fetch the video's details",
        ) from None
    except Exception:
        logger.error("Failed to add gym video for %s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to add gym video",
        ) from None

    avatars = instructor_avatars(classes)
    return card_with_avatar(card, avatars)


@videos_router.delete(
    "/api/v1/gyms/{gym_id}/videos/{video_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a single video from a gym's feed (logged)",
    description=(
        "Remove one video from the gym's served feed by id, and log the removal "
        "(with the optional reason + the actor) to ``gym_video_feed_removal``. "
        "The shared pool row is left untouched (other gyms may still serve it). "
        "Idempotent — removing a video not in the feed still returns 204 and logs "
        "nothing. The request body (`{reason}`) is optional."
    ),
    responses={
        204: {"description": "Removed (or already absent)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def remove_gym_video(
    gym_id: UUID,
    video_id: str,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    owner: bool = Query(False),
    body: VideoRemoveRequest | None = None,
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> None:
    """Remove one video (idempotent → 204): ``owner=true`` ("Your videos")
    deletes it from the owner section (+ owned pool if it's a manual custom);
    else it rejects the latest-run row (with the optional reason)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await videos_service.remove_feed_video(
            gym_id,
            video_id,
            owner=owner,
            reason=body.reason if body else None,
        )
    except Exception:
        logger.error(
            "Failed to remove gym video %s for %s",
            video_id,
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to remove gym video",
        ) from None


@videos_router.post(
    "/api/v1/gyms/{gym_id}/videos/{video_id}/keep",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Keep a rejected video (un-reject)",
    description=(
        "Flip a rejected video back to accepted (returns it to the served feed). "
        "The reject audit is kept as history. Idempotent → 204."
    ),
    responses={
        204: {"description": "Kept (or already accepted)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def keep_gym_video(
    gym_id: UUID,
    video_id: str,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> None:
    """Un-reject a video (back to the served feed); idempotent → 204."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await videos_service.keep_feed_video(gym_id, video_id)
    except Exception:
        logger.error(
            "Failed to keep gym video %s for %s", video_id, gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to keep gym video",
        ) from None


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
    rejected: bool = Query(False),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymFeedPreview:
    """Power the "All" view in one request: hydrate the gym's latest-run feed once
    (``rejected=true`` → the rejected list), group it by genre tag in feed order,
    and return up to ``per_tag`` videos per genre."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        ids = await videos_service.load_feed_ids(gym_id, rejected=rejected)
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
