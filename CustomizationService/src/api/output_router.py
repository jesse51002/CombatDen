"""The two read-only endpoints: a run's output, and one image's bytes."""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse

from src.api.errors import InvalidRunError, NotFoundError
from src.api.schema.output_response import OutputResponse
from src.api.service.output_service import load_output, resolve_image_file

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
        output = await load_output(app_id, run_id)
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
        path = await resolve_image_file(app_id, run_id, slot_id)
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
