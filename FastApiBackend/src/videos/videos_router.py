"""API routes for the videos domain.

A real gym's live content (no prefix — each route declares its full path):

    * ``GET /api/v1/gyms/{gym_id}/videos``              — paginated served feed.
    * ``POST /api/v1/gyms/{gym_id}/videos/lookup``      — fetch a YouTube link's
      real metadata (no write) for the add confirmation.
    * ``POST /api/v1/gyms/{gym_id}/videos``             — add one owner-provided
      YouTube link to the gym's feed (fetches its real metadata).
    * ``DELETE /api/v1/gyms/{gym_id}/videos/{video_id}`` — remove one video from
      the gym's feed (and log the removal + reason).
    * ``POST /api/v1/gyms/{gym_id}/videos/{video_id}/keep`` — un-reject a video.
    * ``GET /api/v1/gyms/{gym_id}/videos/preview``      — the one-shot "All"
      preview (a few videos per genre).
    * ``GET /api/v1/gyms/{gym_id}/videos/spec``         — the gym's live video
      spec.
    * ``GET /api/v1/gyms/{gym_id}/video-spec``          — the gym's latest spec
      (new versioned projection).
    * ``POST /api/v1/gyms/{gym_id}/video-agent``        — one conversational turn.
    * ``POST /api/v1/gyms/{gym_id}/video-agent/refine-from-feed`` — feed→spec
      learning.

Template catalog has moved to ``presets_router`` (``/api/v1/presets/templates``).
The showcase endpoint has moved to ``theme_router`` (``/api/v1/gyms/{id}/showcase``).
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
from src.videos.schema.video_agent_schema import (
    AgentTurnRequest,
    AgentTurnResponse,
)
from src.videos.schema.video_spec_schema import VideoSpecView
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import (
    GymFeedPreview,
    GymFeedSection,
    GymVideoCard,
    GymVideosFeed,
    GymVideoSpecView,
    VideoAddRequest,
    VideoKeepRequest,
    VideoRemoveRequest,
)
from src.videos.service.video_agent.video_agent_service import VideoAgentService
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


# ── A real gym's live feed ────────────────────────────────────────────
# NOTE: Phase 2 — when the member MobileApp repoints here, the
# feed/preview/spec guards must widen to allow gym MEMBERS, not only employees.


@videos_router.get(
    "/api/v1/gyms/{gym_id}/videos",
    response_model=GymVideosFeed,
    summary="Get a page of a gym's served video feed",
    description=(
        "A page of the gym's served feed, hydrated from the shared pool in "
        "relevance order. ``video_type``/``big_group`` filter as expected "
        "(mutually exclusive)."
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
    relevance order. ``owner=true`` → the owner "Your videos" section (else
    the gym's latest scan run); ``rejected=true`` → the rejected list (else
    the served, accepted videos)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )

    try:
        page, total = await videos_service.load_feed_page(
            gym_id,
            owner=owner,
            rejected=rejected,
            video_type=video_type,
            big_group=big_group,
            limit=limit,
            offset=offset,
        )
    except Exception:
        logger.error(
            "Failed to load gym videos for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym videos",
        ) from None

    return GymVideosFeed(total=total, limit=limit, offset=offset, videos=page)


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

    return card


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
    the YouTube Data API) and return its card."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        card = await videos_service.add_feed_video(gym_id, body.url)
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

    return card


@videos_router.delete(
    "/api/v1/gyms/{gym_id}/videos/{video_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Remove a single video from a gym's feed",
    description=(
        "Remove one video from the gym's served feed by id. "
        "``owner=false`` (scan-run feed): rejects the row "
        "(``scan_status='rejected'``, ``curation_type='manual'``) — the shared "
        "pool row is untouched. "
        "``owner=true`` (Your Videos): hard-deletes the feed row (and the pool "
        "row when it's a manually added video). "
        "No removal-log row is written. "
        "Idempotent — removing a video not in the feed returns 204. "
        "The request body ``{reason}`` is optional."
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
        "The reject audit is kept as history. The optional body ``{accept_reason}`` "
        "captures why the owner wants to keep it — the feed-learning refiner uses "
        "this to widen the spec's include criteria. Idempotent → 204."
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
    body: VideoKeepRequest | None = None,
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> None:
    """Un-reject a video (back to the served feed); idempotent → 204."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await videos_service.keep_feed_video(
            gym_id,
            video_id,
            accept_reason=body.accept_reason if body else None,
        )
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
    sections = [
        GymFeedSection(tag=t, videos=by_tag[t])
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


# ── Video spec (LLM authoring surface) ───────────────────────


@videos_router.get(
    "/api/v1/gyms/{gym_id}/video-spec",
    response_model=VideoSpecView,
    summary="Get a gym's latest video spec",
)
@inject
async def get_video_spec(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> VideoSpecView:
    """The gym's latest spec version. 404 when no spec has been authored yet."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    spec = await videos_service.load_latest_spec(gym_id)
    if spec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This gym has no video spec yet.",
        )
    return spec


@videos_router.post(
    "/api/v1/gyms/{gym_id}/video-agent",
    response_model=AgentTurnResponse,
    summary="One conversational turn with the video-spec agent",
)
@inject
async def video_agent_turn(
    gym_id: UUID,
    body: AgentTurnRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoAgentService = Depends(
        Provide[DependencyInjector.video_agent_service]
    ),
) -> AgentTurnResponse:
    """Run one turn: the agent replies with text (its next question) or a finished
    draft to review, plus the serialized history to send back next turn."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await service.agent_turn(gym_id, body)
    except Exception:
        logger.error("video-agent turn failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The video-spec agent failed to respond.",
        ) from None


@videos_router.post(
    "/api/v1/gyms/{gym_id}/video-agent/refine-from-feed",
    response_model=VideoSpecView,
    summary="Refine the video spec from manual feed curation signals",
)
@inject
async def refine_video_spec_from_feed(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> VideoSpecView:
    """Fold unconsumed manual curation signals into a new ``feed_update`` spec
    version. 404 when there is no existing spec or no new signals to learn from."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        result = await videos_service.refine_from_feed(gym_id)
    except Exception:
        logger.error("feed-refine failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The feed-learning refiner failed.",
        ) from None
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No new feed curation to learn from.",
        )
    return result
