"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.schema.member_details_schema import (
    MemberDetailResponse,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembersListTotalCounts,
)
from src.members.service.member_details_service import (
    MemberService,
)
from src.members.service.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

members_router = APIRouter(
    prefix="/api/v1/members",
    tags=["members"],
)


@members_router.get(
    "/member_details",
    response_model=MemberDetailResponse,
    summary="Get member detail",
    description=("Returns full member detail for the Specific Member screen."),
    responses={
        200: {"description": "Member detail retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": ("Not authorized to view this member")},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_detail(
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    member_service: MemberService = Depends(Provide[DependencyInjector.member_service]),
) -> MemberDetailResponse:
    """Get full detail for a specific member.

    Args:
        crm_user_id: The member's CRM user ID.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        member_service: Injected member service.

    Returns:
        MemberDetailResponse with all screen sections.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized to view this member,
            404 if member not found.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await member_service.get_member_detail(
            crm_user_id=crm_user_id,
        )
    except ValueError as exc:
        logger.error(
            "Member not found: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to get member detail: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve member detail",
        ) from None


@members_router.post(
    "/crm_members_list",
    response_model=CrmMembersListResponse,
    summary="Get CRM members list",
    description=(
        "Returns a filtered, sorted, paginated list of gym "
        "members for the CRM members list screen."
    ),
    responses={
        200: {"description": "Members list retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": ("Not authorized to access this gym")},
    },
)
@inject
async def crm_members_list(
    request: CrmMembersListRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crm_members_list_service: CrmMembersListService = Depends(
        Provide[DependencyInjector.crm_members_list_service]
    ),
) -> CrmMembersListResponse:
    """Get filtered, paginated members list for the CRM screen.

    Args:
        request: Members list request with view, filters,
            and pagination params.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        crm_members_list_service: Injected members list service.

    Returns:
        CrmMembersListResponse with pre-formatted rows.

    Raises:
        HTTPException: 401 if not authenticated,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await crm_members_list_service.get_crm_members_list(request)
    except Exception:
        logger.error(
            "Failed to get members list: gym_id=%s, view=%s",
            request.gym_id,
            request.requested_view,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve members list",
        ) from None


@members_router.get(
    "/crm_total_counts",
    response_model=MembersListTotalCounts,
    summary="Get CRM member total counts",
    description=("Returns unfiltered member counts per status for the CRM members list subtitle."),
    responses={
        200: {"description": "Total counts retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": ("Not authorized to access this gym")},
    },
)
@inject
async def crm_total_counts(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    total_counts_service: CrmTotalCountsService = Depends(
        Provide[DependencyInjector.crm_total_counts_service]
    ),
) -> MembersListTotalCounts:
    """Get unfiltered member counts per status.

    Args:
        gym_id: The gym to count members for.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        total_counts_service: Injected total counts service.

    Returns:
        MembersListTotalCounts with active, trial,
        frozen, overdue.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await total_counts_service.get_total_counts(gym_id)
    except Exception:
        logger.error(
            "Failed to get total counts: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve total counts",
        ) from None
