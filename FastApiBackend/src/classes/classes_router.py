"""API routes for the classes domain."""

import logging
from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.classes.schema.classes_checkin_schema import (
    ClassesCheckinRequest,
    ClassesCheckinResponse,
)
from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

classes_router = APIRouter(
    prefix="/api/v1/classes",
    tags=["classes"],
)


@classes_router.post(
    "/checkin",
    response_model=ClassesCheckinResponse,
    summary="Check a member into a class",
    description=(
        "Selects the best eligible membership plan and logs "
        "the class attendance. Returns full membership breakdown. "
        "If no eligible plan is found, returns null for log_id "
        "and chosen_plan_id with the membership breakdown."
    ),
    responses={
        200: {"description": "Check-in result returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to access this gym"},
    },
)
@inject
async def checkin(
    request: ClassesCheckinRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    checkin_service: ClassesCheckinService = Depends(Provide[DependencyInjector.checkin_service]),
) -> ClassesCheckinResponse:
    """Check a member into a class.

    Args:
        request: Member, gym, and class identifiers.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        checkin_service: Injected check-in service.

    Returns:
        ClassesCheckinResponse with chosen plan and breakdown.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.crm_user_id, user_payload)

    try:
        return await checkin_service.checkin(request)
    except Exception:
        logger.error(
            "Failed to check in: gym_id=%s, crm_user_id=%s, class_id=%s",
            request.gym_id,
            request.crm_user_id,
            request.class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record check-in",
        ) from None
