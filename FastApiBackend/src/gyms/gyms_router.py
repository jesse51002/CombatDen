"""API routes for the gyms domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.gyms.schema.gyms_schema import (
    GymCreateRequest,
    GymCreateResponse,
    GymResponse,
    GymUpdateRequest,
)
from src.gyms.service.gyms_service import GymsService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

gyms_router = APIRouter(
    prefix="/api/v1/gyms",
    tags=["gyms"],
)


@gyms_router.post(
    "/",
    response_model=GymCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a gym",
    description=(
        "Creates a gym row and the calling user's owner "
        "``gym_employees`` record in a single transaction."
    ),
    responses={
        201: {"description": "Gym created"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
    },
)
@inject
async def create_gym(
    request: GymCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymCreateResponse:
    """Create a gym and owner record."""
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])

    try:
        return await gyms_service.create_gym(request=request, user_id=user_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create gym for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create gym",
        ) from None


@gyms_router.get(
    "/me",
    response_model=GymResponse,
    summary="Get the caller's gym",
    description="Returns the gym the caller is an employee of.",
    responses={
        200: {"description": "Gym retrieved"},
        401: {"description": "Not authenticated"},
        404: {"description": "No gym found for this user"},
    },
)
@inject
async def get_my_gym(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymResponse:
    """Return the caller's gym."""
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])

    try:
        return await gyms_service.get_gym_for_user(user_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to get gym for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve gym",
        ) from None


@gyms_router.put(
    "/{gym_id}",
    response_model=GymResponse,
    summary="Update a gym",
    description="Updates the gym name, description, or timezone.",
    responses={
        200: {"description": "Gym updated"},
        400: {"description": "Invalid update payload"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Gym not found"},
    },
)
@inject
async def update_gym(
    gym_id: UUID,
    request: GymUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymResponse:
    """Update a gym's mutable fields."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await gyms_service.update_gym(gym_id, request.data)
    except ValueError as exc:
        msg = str(exc)
        if "not found" in msg.lower():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=msg,
        ) from None
    except Exception:
        logger.error(
            "Failed to update gym: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update gym",
        ) from None
