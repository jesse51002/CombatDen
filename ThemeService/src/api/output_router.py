"""The read-only endpoints: a run's output, one image's bytes, and the
per-slot font delivery payload."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import FileResponse, RedirectResponse

from src.api.config import settings
from src.api.errors import InvalidRunError, NotFoundError
from src.api.schema.font_delivery import FontDeliveryResponse
from src.api.schema.output_response import OutputResponse
from src.api.schema.style_list_response import StyleListResponse
from src.api.service.font_service import font_service
from src.api.service.output_service import output_service
from src.core.asset_urls import cdn_url, icon_key, image_key

logger = logging.getLogger(__name__)

output_router = APIRouter(prefix="/apps", tags=["output"])

# Asset URLs are stable across regenerations (a preset's run id doesn't
# change, and re-runs overwrite the same files), so without this clients
# would sit on the cache manager's ~7-day default freshness window and
# miss owner updates for a week. One day lets a swap (e.g. a Christmas
# logo) propagate within ~24h: clients serve the cached file instantly,
# and once the day lapses the next view revalidates (ETag/Last-Modified
# are set by FileResponse) and picks up the new bytes — still serving the
# cached file when offline.
_ASSET_CACHE_CONTROL = {"Cache-Control": "max-age=86400"}


# Declared before `/{app_id}/{run_id}` so the literal `styles` segment
# isn't captured as a run id (Starlette matches in declaration order).
@output_router.get(
    "/{app_id}/styles",
    response_model=StyleListResponse,
    summary="List an app's selectable styles (paginated, searchable)",
    responses={
        200: {
            "description": (
                "One page of the named styles (design name + celebration "
                "image URL) with the post-filter total; date-stamped runs "
                "are excluded"
            )
        },
        404: {"description": "No such app"},
    },
)
async def list_styles(
    app_id: str,
    offset: int = Query(0, ge=0, description="Index of the first item"),
    limit: int = Query(
        20, ge=1, le=100, description="Max items in this page"
    ),
    q: str | None = Query(
        None,
        description=(
            "Case-insensitive substring match on id or display name. "
            "Empty / unset returns every style."
        ),
    ),
) -> StyleListResponse:
    """Return one page of the app's named presets a picker can switch
    between. ``offset`` + ``limit`` paginate; ``q`` filters by id or
    display name."""
    try:
        return await output_service().list_styles(
            app_id, offset=offset, limit=limit, query=q
        )
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to list styles for %s", app_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list styles",
        ) from None


@output_router.get(
    "/{app_id}/{run_id}",
    response_model=OutputResponse,
    summary="Get a run's resolved customization",
    responses={
        200: {"description": "The run's output (colours + image URLs)"},
        404: {"description": "No such app/run"},
        422: {"description": "Run exists but its output.yaml is stale"},
    },
)
async def get_output(app_id: str, run_id: str) -> OutputResponse:
    """Return one run's ``output.yaml`` with streamable image URLs."""
    try:
        output = await output_service().load(app_id, run_id)
        return OutputResponse.from_output(
            output, app_id, run_id, settings.assets_cdn_base_url
        )
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to load output for %s/%s", app_id, run_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load output",
        ) from None


@output_router.get(
    "/{app_id}/{run_id}/images/{slot_id}",
    response_class=FileResponse,
    summary="Stream one image slot's PNG",
    responses={
        200: {"content": {"image/png": {}}, "description": "The PNG bytes"},
        404: {"description": "No such app/run/slot or image file"},
        422: {"description": "Run exists but its output.yaml is stale"},
    },
)
async def get_image(
    app_id: str, run_id: str, slot_id: str
) -> FileResponse:
    """Stream the generated PNG for one declared image slot. When a CDN is
    configured the bytes live on S3, so this legacy endpoint just redirects
    there (a safety net for stale clients; the styles/output JSON already
    carries the absolute CDN URL)."""
    try:
        if settings.assets_cdn_base_url:
            return RedirectResponse(
                cdn_url(settings.assets_cdn_base_url, image_key(app_id, run_id, slot_id)),
                status_code=status.HTTP_307_TEMPORARY_REDIRECT,
            )
        path = await output_service().image_file(app_id, run_id, slot_id)
        return FileResponse(
            path, media_type="image/png", headers=_ASSET_CACHE_CONTROL
        )
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to serve image %s/%s/%s",
            app_id,
            run_id,
            slot_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to serve image",
        ) from None


@output_router.get(
    "/{app_id}/{run_id}/icons/{slot_id}",
    response_class=FileResponse,
    summary="Stream one icon slot's SVG",
    responses={
        200: {
            "content": {"image/svg+xml": {}},
            "description": "The SVG bytes",
        },
        404: {"description": "No such app/run/slot or icon file"},
        422: {"description": "Run exists but its output.yaml is stale"},
    },
)
async def get_icon(
    app_id: str, run_id: str, slot_id: str
) -> FileResponse:
    """Stream the resolved monochrome SVG for one declared icon slot. Redirects
    to the CDN when one is configured (bytes live on S3); otherwise serves the
    local file."""
    try:
        if settings.assets_cdn_base_url:
            return RedirectResponse(
                cdn_url(settings.assets_cdn_base_url, icon_key(app_id, run_id, slot_id)),
                status_code=status.HTTP_307_TEMPORARY_REDIRECT,
            )
        path = await output_service().icon_file(app_id, run_id, slot_id)
        return FileResponse(
            path, media_type="image/svg+xml", headers=_ASSET_CACHE_CONTROL
        )
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to serve icon %s/%s/%s",
            app_id,
            run_id,
            slot_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to serve icon",
        ) from None


@output_router.get(
    "/{app_id}/{run_id}/fonts/{slot_id}",
    response_model=FontDeliveryResponse,
    summary="Get the deliverable Google Font payload for one font slot",
    responses={
        200: {
            "description": (
                "Family, category, CSS URL and per-variant TTF URLs on "
                "fonts.gstatic.com (browsers can hit the CSS URL for "
                "woff2)"
            )
        },
        404: {
            "description": (
                "No such app/run/slot, or the picked family is no longer "
                "in the Google Fonts catalog"
            )
        },
        422: {"description": "Run exists but its output.yaml is stale"},
    },
)
async def get_font(
    app_id: str, run_id: str, slot_id: str
) -> FontDeliveryResponse:
    """Return the Google Fonts payload (family + per-variant URLs) for
    one declared font slot. ``variants`` carries TTF URLs the frontend
    can fetch from Google's CDN directly; ``css_url`` is the CSS2
    endpoint browsers can drop in for woff2."""
    try:
        return await font_service().resolve(app_id, run_id, slot_id)
    except NotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except InvalidRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to resolve font %s/%s/%s",
            app_id,
            run_id,
            slot_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to resolve font",
        ) from None
