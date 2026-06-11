"""API routes for the membership plans domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.payments.payments_exceptions import PaymentsStripeError
from src.plans.plans_schema import (
    MembershipPlanCreateRequest,
    MembershipPlanMigrateAllRequest,
    MembershipPlanMigrateRequest,
    MembershipPlanPriceRequest,
    MembershipPlanPriceResponse,
    MembershipPlanPriceWithCount,
    MembershipPlanResponse,
    MembershipPlanUpdateRequest,
)
from src.plans.service.plans_service import (
    MembershipPlansService,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

membership_plans_router = APIRouter(
    prefix="/api/v1/membership_plans",
    tags=["membership_plans"],
)


# ── Create ─────────────────────────────────────────────────────


@membership_plans_router.post(
    "/",
    response_model=MembershipPlanResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a membership plan",
    description="Creates a membership plan with an initial price in Stripe and CRM.",
    responses={
        201: {"description": "Plan created successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def create_plan(
    request: MembershipPlanCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> MembershipPlanResponse:
    """Create a new membership plan.

    Args:
        request: Plan creation data.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 400/401/403/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await plans_service.create_plan(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create plan for gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create plan",
        ) from None


# ── Update ─────────────────────────────────────────────────────


@membership_plans_router.put(
    "/",
    response_model=MembershipPlanResponse,
    status_code=status.HTTP_200_OK,
    summary="Update a membership plan",
    description="Updates plan metadata in Stripe and CRM.",
    responses={
        200: {"description": "Plan updated successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Plan not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def update_plan(
    request: MembershipPlanUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> MembershipPlanResponse:
    """Update an existing membership plan.

    Args:
        request: Plan update data.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 400/401/403/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await plans_service.update_plan(request)
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
            "Failed to update plan %s",
            request.plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update plan",
        ) from None


# ── Delete ─────────────────────────────────────────────────────


@membership_plans_router.delete(
    "/",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a membership plan",
    description="Soft-deletes a membership plan and deactivates its Stripe product.",
    responses={
        204: {"description": "Plan deleted successfully"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Plan not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def delete_plan(
    plan_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> None:
    """Soft-delete a membership plan.

    Args:
        plan_id: The plan to delete.
        gym_id: The gym owning the plan.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 400/401/403/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await plans_service.delete_plan(plan_id, gym_id)
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
            "Failed to delete plan %s",
            plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete plan",
        ) from None


# ── List ───────────────────────────────────────────────────────


@membership_plans_router.get(
    "/",
    response_model=list[MembershipPlanResponse],
    status_code=status.HTTP_200_OK,
    summary="List membership plans",
    description="Lists all non-deleted plans for a gym with their active prices.",
    responses={
        200: {"description": "Plans listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_plans(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> list[MembershipPlanResponse]:
    """List all plans for a gym.

    Args:
        gym_id: The gym to list plans for.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await plans_service.list_plans(gym_id)
    except Exception:
        logger.error(
            "Failed to list plans for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list plans",
        ) from None


# ── Get ────────────────────────────────────────────────────────


@membership_plans_router.get(
    "/{plan_id}",
    response_model=MembershipPlanResponse,
    status_code=status.HTTP_200_OK,
    summary="Get a membership plan",
    description="Fetches a single plan with its active price.",
    responses={
        200: {"description": "Plan fetched successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Plan not found"},
    },
)
@inject
async def get_plan(
    plan_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> MembershipPlanResponse:
    """Get a single plan.

    Args:
        plan_id: The plan to fetch.
        gym_id: The gym owning the plan.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await plans_service.get_plan(plan_id, gym_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to get plan %s",
            plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get plan",
        ) from None


# ── List Prices ────────────────────────────────────────────────


@membership_plans_router.get(
    "/{plan_id}/prices",
    response_model=list[MembershipPlanPriceWithCount],
    status_code=status.HTTP_200_OK,
    summary="List a plan's price versions",
    description=(
        "Lists every price version of a plan (active first) with the "
        "number of members still on each — so the CRM can show older "
        "prices that still have members to migrate forward."
    ),
    responses={
        200: {"description": "Prices fetched successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Plan not found"},
    },
)
@inject
async def list_plan_prices(
    plan_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> list[MembershipPlanPriceWithCount]:
    """List a plan's price versions with per-price member counts.

    Args:
        plan_id: The plan whose prices to list.
        gym_id: The gym owning the plan.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await plans_service.list_prices(plan_id, gym_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to list prices for plan %s",
            plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list plan prices",
        ) from None


# ── Set Price ──────────────────────────────────────────────────


@membership_plans_router.post(
    "/price",
    response_model=MembershipPlanPriceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Set plan price",
    description=(
        "Creates a new price for a plan. Existing members keep their "
        "old price — use the migrate endpoints to move them."
    ),
    responses={
        201: {"description": "Price set successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Plan not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def set_price(
    request: MembershipPlanPriceRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    plans_service: MembershipPlansService = Depends(
        Provide[DependencyInjector.membership_plans_service]
    ),
) -> MembershipPlanPriceResponse:
    """Set / update the active price on a plan.

    Args:
        request: Plan ID, gym ID, and new price in cents.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        plans_service: Injected plans service.

    Raises:
        HTTPException: 400/401/403/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await plans_service.set_price(request)
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
            "Failed to set price for plan %s",
            request.plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to set price",
        ) from None


# ── Migrate (specific members) ─────────────────────────────────


@membership_plans_router.post(
    "/migrate",
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Migrate specific members (not implemented)",
    description="Member migration is not implemented yet.",
    responses={
        501: {"description": "Member migration is not implemented yet"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def migrate_members(
    request: MembershipPlanMigrateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
) -> None:
    """Not implemented yet — member migration is pending backend work.

    Raises:
        HTTPException: 401/403 on auth, otherwise 501 Not Implemented.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Member migration is not implemented yet.",
    )


# ── Migrate All ────────────────────────────────────────────────


@membership_plans_router.post(
    "/migrate-all",
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    summary="Migrate all members on a plan (not implemented)",
    description="Member migration is not implemented yet.",
    responses={
        501: {"description": "Member migration is not implemented yet"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def migrate_all_members(
    request: MembershipPlanMigrateAllRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
) -> None:
    """Not implemented yet — member migration is pending backend work.

    Raises:
        HTTPException: 401/403 on auth, otherwise 501 Not Implemented.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Member migration is not implemented yet.",
    )
