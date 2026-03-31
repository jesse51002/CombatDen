"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.members_schemas import MemberDetailResponse
from src.members.members_service import MemberService
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
    description="Returns full member detail for the Specific Member screen.",
    responses={
        200: {"description": "Member detail retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
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
        logger.debug("Log test")
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
