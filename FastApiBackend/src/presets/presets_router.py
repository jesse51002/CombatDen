"""API routes for the presets domain.

    * ``POST /api/v1/gyms/{gym_id}/presets/import`` — import a template into the
      gym's production tables (owner + allowlist).

Template catalog (public, no auth):

    * ``GET /api/v1/presets/templates``                         — page the
      slug-keyed template catalog.
    * ``GET /api/v1/presets/templates/{video_gym_id}``          — one template's
      full detail (spec, classes, rewards).
    * ``GET /api/v1/presets/templates/{video_gym_id}/videos``   — a page of the
      template's video feed.
    * ``GET /api/v1/presets/templates/{video_gym_id}/videos/preview`` — the
      one-shot "All" preview (a few videos per genre).
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from schema.video import VideoGenre

from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.presets.schema.presets_schema import (
    PresetImportRequest,
    PresetImportResponse,
)
from src.presets.schema.presets_templates_schema import (
    VideoTemplateCatalogPage,
    VideoTemplateDetail,
)
from src.presets.service.presets_template_service import PresetsTemplateService
from src.shared.auth import Auth, security
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import (
    GymFeedPreview,
    GymFeedSection,
    GymVideoCard,
    GymVideosFeed,
)
from src.videos.service.videos_service import VideosService

logger = logging.getLogger(__name__)

presets_router = APIRouter(tags=["presets"])

# Page size when the client doesn't ask.
DEFAULT_LIMIT = 20
MAX_LIMIT = 100
# Videos per genre in the one-shot "All" preview.
PREVIEW_PER_TAG = 10


# ── Template import ────────────────────────────────────────────────────────────


@presets_router.post(
    "/api/v1/gyms/{gym_id}/presets/import",
    response_model=PresetImportResponse,
    status_code=status.HTTP_200_OK,
    summary="Import a video template into a gym's production tables",
    description=(
        "Transactionally copies the chosen ``template_gym`` template's spec, "
        "queries, feed, classes, instructors, and rewards into the gym's "
        "real production tables, and re-images the gym's existing membership "
        "plans with the imported class photos. Re-pickable: calling again "
        "overwrites the prior import. Restricted to gym owners AND the "
        "preset-import email allowlist (``preset_import_allowed_emails`` "
        "setting)."
    ),
    responses={
        200: {"description": "Import complete — counts in the response body"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not a gym owner, or not on the import allowlist"},
        404: {"description": "Template not found"},
        500: {"description": "Import failed"},
    },
)
@inject
async def import_preset(
    gym_id: UUID,
    request: PresetImportRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    presets_service=Depends(Provide[DependencyInjector.presets_service]),
) -> PresetImportResponse:
    """Import a template_gym template into the gym's production tables."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_owner(gym_id, user_payload)

    email: str | None = user_payload.get("email")
    allowed: set[str] = {
        e.strip()
        for e in settings.preset_import_allowed_emails.split(",")
        if e.strip()
    }
    if not email or email not in allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Preset import is restricted",
        )

    try:
        return await presets_service.import_template(
            gym_id=gym_id,
            video_gym_id=request.video_gym_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to import preset for gym_id=%s video_gym_id=%r",
            gym_id,
            request.video_gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to import preset",
        ) from None


# ── Template catalog (public, no auth) ────────────────────────────────────────


@presets_router.get(
    "/api/v1/presets/templates",
    response_model=VideoTemplateCatalogPage,
    summary="Page the video template catalog (public)",
    description=(
        "A page of slim template cards (the slug-keyed ``template_gym`` catalog "
        "the preset import copies from). Each carries its theme; ``total`` is "
        "the template count before pagination. ``query`` filters on slug / "
        "theme / discipline. Public (no auth)."
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
    presets_template_service: PresetsTemplateService = Depends(
        Provide[DependencyInjector.presets_template_service]
    ),
) -> VideoTemplateCatalogPage:
    """Return one page of the template catalog (public)."""
    try:
        return await presets_template_service.list_template_cards(
            limit=limit, offset=offset, query=query
        )
    except Exception:
        logger.error("Failed to list video templates", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list video templates",
        ) from None


@presets_router.get(
    "/api/v1/presets/templates/{video_gym_id}",
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
    presets_template_service: PresetsTemplateService = Depends(
        Provide[DependencyInjector.presets_template_service]
    ),
) -> VideoTemplateDetail:
    """Return one template's full detail by slug (public)."""
    try:
        detail = await presets_template_service.load_template(video_gym_id)
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


@presets_router.get(
    "/api/v1/presets/templates/{video_gym_id}/videos",
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
    presets_template_service: PresetsTemplateService = Depends(
        Provide[DependencyInjector.presets_template_service]
    ),
) -> GymVideosFeed:
    """Return one page of a template's feed, filtered and paginated at the DB.
    ``rejected=true`` serves the scan's rejected list (admin review)."""
    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )
    try:
        detail = await presets_template_service.load_template(video_gym_id)
        if detail is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No template {video_gym_id!r}",
            )
        page, total = await presets_template_service.load_template_feed_page(
            video_gym_id,
            rejected=rejected,
            video_type=video_type,
            big_group=big_group,
            limit=limit,
            offset=offset,
        )
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

    return GymVideosFeed(total=total, limit=limit, offset=offset, videos=page)


@presets_router.get(
    "/api/v1/presets/templates/{video_gym_id}/videos/preview",
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
    presets_template_service: PresetsTemplateService = Depends(
        Provide[DependencyInjector.presets_template_service]
    ),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymFeedPreview:
    """The template's "All" preview: its feed grouped by genre, capped per genre.
    ``rejected=true`` previews the scan's rejected list."""
    try:
        detail = await presets_template_service.load_template(video_gym_id)
        if detail is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No template {video_gym_id!r}",
            )
        ids = await presets_template_service.load_template_feed_ids(
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
    by_tag: dict[VideoGenre, list[GymVideoCard]] = {}
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
