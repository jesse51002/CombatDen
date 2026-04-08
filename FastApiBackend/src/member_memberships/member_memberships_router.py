"""API routes for the member memberships domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.member_memberships.service.member_memberships_service import (
    MemberMembershipsService,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

member_memberships_router = APIRouter(
    prefix="/api/v1/member_memberships",
    tags=["member_memberships"],
)


@member_memberships_router.delete(
    "/",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Cancel a membership",
    description=(
        "Cancels a specific active membership for a member. "
        "Sets cancel_date and end_date to the membership's "
        "next_due_date, or today if next_due_date is missing "
        "or in the past."
    ),
    responses={
        204: {"description": "Membership cancelled successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def cancel_membership(
    crm_user_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Cancel a specific membership for a member.

    Args:
        crm_user_id: The member.
        gym_id: The gym.
        plan_id: The membership plan to cancel.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        await memberships_service.cancel(
            crm_user_id,
            gym_id,
            plan_id,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg.lower():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg,
        ) from None
    except Exception:
        logger.error(
            "Failed to cancel membership: crm_user_id=%s, gym_id=%s, plan_id=%s",
            crm_user_id,
            gym_id,
            plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel membership",
        ) from None
