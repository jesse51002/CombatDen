"""The read-only endpoints: a run's output, one image's bytes, and the
per-slot font delivery payload."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse

from src.api.errors import InvalidRunError, NotFoundError
from src.api.schema.font_delivery import FontDeliveryResponse
from src.api.schema.output_response import OutputResponse
from src.api.service.font_service import font_service
from src.api.service.output_service import output_service

logger = logging.getLogger(__name__)

output_router = APIRouter(prefix="/apps", tags=["output"])


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
        return OutputResponse.from_output(output, app_id, run_id)
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
    """Stream the generated PNG for one declared image slot."""
    try:
        path = await output_service().image_file(app_id, run_id, slot_id)
        return FileResponse(path, media_type="image/png")
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
