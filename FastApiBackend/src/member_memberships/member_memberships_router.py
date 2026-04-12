"""API routes for the member memberships domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsFreezeRequest,
    MemberMembershipsStartRequest,
    MemberMembershipsUnfreezeRequest,
    MemberMembershipsUpdatePriceRequest,
)
from src.member_memberships.service.member_memberships_service import (
    MemberMembershipsService,
)
from src.payments.payments_exceptions import PaymentsStripeError
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
        "Sets cancel_date to the membership's next_due_date, "
        "or today if next_due_date is missing or in the past."
    ),
    responses={
        204: {"description": "Membership cancelled successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def cancel_membership(
    item_id: UUID,
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Cancel a specific membership for a member.

    Syncs the cancellation to Stripe first, then updates the
    CRM database.

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
            502 on Stripe errors,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        await memberships_service.cancel(item_id, crm_user_id)
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
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to cancel membership: item_id=%s, crm_user_id=%s",
            item_id,
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel membership",
        ) from None


@member_memberships_router.post(
    "/freeze",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Freeze a member's account",
    description=(
        "Freezes billing for a member's account (account-level). "
        "Accepts any family member's crm_user_id and resolves "
        "to the paying parent. Idempotent — re-freezing updates "
        "the freeze end date."
    ),
    responses={
        204: {"description": "Account frozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def freeze_membership(
    request: MemberMembershipsFreezeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Freeze a member's account.

    Args:
        request: Freeze request with crm_user_id, gym_id, freeze_months.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.crm_user_id, user_payload)

    try:
        await memberships_service.freeze(
            request.crm_user_id,
            request.gym_id,
            request.freeze_months,
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
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to freeze account: crm_user_id=%s, gym_id=%s",
            request.crm_user_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to freeze account",
        ) from None


@member_memberships_router.post(
    "/unfreeze",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unfreeze a member's account",
    description=(
        "Resumes billing for a member's account (account-level). "
        "If not frozen, performs a no-op sync for consistency."
    ),
    responses={
        204: {"description": "Account unfrozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def unfreeze_membership(
    request: MemberMembershipsUnfreezeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Unfreeze a member's account.

    Args:
        request: Unfreeze request with crm_user_id, gym_id.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.crm_user_id, user_payload)

    try:
        await memberships_service.unfreeze(
            request.crm_user_id,
            request.gym_id,
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
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to unfreeze account: crm_user_id=%s, gym_id=%s",
            request.crm_user_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unfreeze account",
        ) from None


@member_memberships_router.post(
    "/",
    status_code=status.HTTP_201_CREATED,
    summary="Start a new membership",
    description=(
        "Creates a new membership for a member. Validates "
        "the plan/price, checks for duplicates and frozen "
        "accounts, syncs to Stripe, then inserts the CRM row."
    ),
    responses={
        201: {"description": "Membership created successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def start_membership(
    request: MemberMembershipsStartRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Start a new membership for a member.

    Args:
        request: Start request with plan, price, and start date.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.crm_user_id, user_payload)

    try:
        await memberships_service.start(
            crm_user_id=request.crm_user_id,
            gym_id=request.gym_id,
            plan_id=request.plan_id,
            price_id=request.price_id,
            start_date=request.start_date,
            discount_ids=request.discount_ids,
            include_linked_discount=request.include_linked_discount,
            prorate=request.prorate,
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
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to start membership: crm_user_id=%s, gym_id=%s, plan_id=%s",
            request.crm_user_id,
            request.gym_id,
            request.plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to start membership",
        ) from None


@member_memberships_router.put(
    "/price",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Update membership price",
    description=(
        "Switches a membership to a different price tier. "
        "Swaps the old price for the new one in Stripe, "
        "then updates the CRM row."
    ),
    responses={
        204: {"description": "Price updated successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def update_membership_price(
    request: MemberMembershipsUpdatePriceRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Update the price of an existing membership.

    Args:
        request: Update price request with new price ID and prorate flag.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.crm_user_id, user_payload)

    try:
        await memberships_service.update_price(
            item_id=request.item_id,
            crm_user_id=request.crm_user_id,
            new_price_id=request.new_price_id,
            prorate=request.prorate,
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
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to update membership price: item_id=%s, crm_user_id=%s",
            request.item_id,
            request.crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update membership price",
        ) from None
