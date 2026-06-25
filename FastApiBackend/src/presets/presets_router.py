"""API routes for the presets domain.

This router is demo-gated to an email allowlist
(``settings.preset_import_allowed_emails``) for now, but the import itself is a
real production write path — it copies a video_gym template into a real gym's
production tables in one transaction.

Endpoint:

    * ``POST /api/v1/gyms/{gym_id}/presets/import`` — import a template into the
      gym's production tables (owner + allowlist).
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.config import settings
from src.core.dependencies import DependencyInjector
from src.presets.schema.presets_schema import (
    PresetImportRequest,
    PresetImportResponse,
)
from src.presets.service.presets_service import PresetsService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

presets_router = APIRouter(tags=["presets"])


@presets_router.post(
    "/api/v1/gyms/{gym_id}/presets/import",
    response_model=PresetImportResponse,
    status_code=status.HTTP_200_OK,
    summary="Import a video template into a gym's production tables",
    description=(
        "Transactionally copies the chosen ``video_gym`` template's spec, "
        "queries, feed, classes, instructors, and rewards into the gym's "
        "real production tables. Re-pickable: calling again overwrites the "
        "prior import. Restricted to gym owners AND the preset-import "
        "email allowlist (``preset_import_allowed_emails`` setting)."
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
    presets_service: PresetsService = Depends(
        Provide[DependencyInjector.presets_service]
    ),
) -> PresetImportResponse:
    """Import a video_gym template into the gym's production tables."""
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
