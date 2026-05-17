"""API routes for the classes domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.classes.schema.classes_schema import (
    CheckinRequest,
    CheckinResponse,
    StreakResponse,
)
from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.classes.service.classes_streak_service import ClassesStreakService
from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

classes_router = APIRouter(
    prefix="/api/v1/classes",
    tags=["classes"],
)


@classes_router.post(
    "/checkin",
    response_model=CheckinResponse,
    summary="Check a member into a class instance",
    description=(
        "Inserts a row in ``member_attendance`` and bumps the "
        "member's ``last_class`` to the class_history occurred_at. "
        "Idempotent — a second call for the same "
        "(member_id, class_history_id) returns the existing log_id "
        "with ``already_checked_in = True``."
    ),
    responses={
        200: {"description": "Check-in recorded"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def checkin(
    request: CheckinRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    checkin_service: ClassesCheckinService = Depends(Provide[DependencyInjector.checkin_service]),
) -> CheckinResponse:
    """Record attendance."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await checkin_service.checkin(request)
    except Exception:
        logger.error(
            "Check-in failed: member_id=%s, class_history_id=%s",
            request.member_id,
            request.class_history_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record check-in",
        ) from None


@classes_router.get(
    "/streak",
    response_model=StreakResponse,
    summary="Get a member's class attendance streak",
    responses={
        200: {"description": "Streak retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def get_streak(
    member_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    streak_service: ClassesStreakService = Depends(Provide[DependencyInjector.streak_service]),
) -> StreakResponse:
    """Weeks of consecutive class attendance."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        weeks = await streak_service.get_streak(member_id, gym_id)
    except Exception:
        logger.error(
            "Streak query failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve streak",
        ) from None

    return StreakResponse(member_id=member_id, class_streak_weeks=weeks)
