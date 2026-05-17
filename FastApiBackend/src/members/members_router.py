"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.schema.members_schema import (
    MemberCreateRequest,
    MemberDetailResponse,
    MemberListResponse,
    MemberResponse,
    MembersListRequest,
    MembersTotalCounts,
    MemberUpdateRequest,
)
from src.members.service.members_service import MembersService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

members_router = APIRouter(
    prefix="/api/v1/members",
    tags=["members"],
)


@members_router.post(
    "/",
    response_model=MemberResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a member",
    responses={
        201: {"description": "Member created"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_member(
    request: MemberCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    members_service: MembersService = Depends(Provide[DependencyInjector.members_service]),
) -> MemberResponse:
    """Create a member shell. Gym staff only."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await members_service.create_member(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create member for gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create member",
        ) from None


@members_router.put(
    "/{member_id}",
    response_model=MemberResponse,
    summary="Update a member",
    responses={
        200: {"description": "Member updated"},
        400: {"description": "Invalid update"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def update_member(
    member_id: UUID,
    request: MemberUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    members_service: MembersService = Depends(Provide[DependencyInjector.members_service]),
) -> MemberResponse:
    """Update a member's mutable fields."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await members_service.update_member(member_id, request.data)
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
            "Failed to update member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update member",
        ) from None


@members_router.post(
    "/list",
    response_model=MemberListResponse,
    summary="List members for a gym",
    description=(
        "Returns a filtered, paginated list of members for the "
        "AppManagement members screen. Status comes from the "
        "``members_with_status`` view."
    ),
    responses={
        200: {"description": "Members list retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_members(
    request: MembersListRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    members_service: MembersService = Depends(Provide[DependencyInjector.members_service]),
) -> MemberListResponse:
    """Paginated members list."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await members_service.list_members(request)
    except Exception:
        logger.error(
            "Failed to list members: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve members",
        ) from None


@members_router.get(
    "/counts",
    response_model=MembersTotalCounts,
    summary="Unfiltered member counts per status",
    responses={
        200: {"description": "Counts retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def total_counts(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    members_service: MembersService = Depends(Provide[DependencyInjector.members_service]),
) -> MembersTotalCounts:
    """Total counts per status for a gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await members_service.total_counts(gym_id)
    except Exception:
        logger.error(
            "Failed to get total counts: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve counts",
        ) from None


@members_router.get(
    "/{member_id}",
    response_model=MemberDetailResponse,
    summary="Get member detail",
    description=("Full member detail including redeemed rewards and class streak."),
    responses={
        200: {"description": "Member detail retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_detail(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    members_service: MembersService = Depends(Provide[DependencyInjector.members_service]),
) -> MemberDetailResponse:
    """Full member detail."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await members_service.get_member_detail(member_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to get member detail: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve member detail",
        ) from None
