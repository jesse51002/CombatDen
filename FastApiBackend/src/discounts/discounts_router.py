"""API routes for the discounts domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountUpdateRequest,
)
from src.discounts.service.discounts_service import DiscountsService
from src.payments.payments_exceptions import PaymentsStripeError
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

discounts_router = APIRouter(
    prefix="/api/v1/discounts",
    tags=["discounts"],
)


@discounts_router.post(
    "/",
    response_model=DiscountResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a discount",
    description="Creates a gym discount with a corresponding Stripe coupon.",
    responses={
        201: {"description": "Discount created successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def create_discount(
    request: DiscountCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> DiscountResponse:
    """Create a new gym discount.

    Args:
        request: Discount creation data.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await discounts_service.create_discount(request)
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
            "Failed to create discount for gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create discount",
        ) from None


@discounts_router.put(
    "/",
    response_model=DiscountResponse,
    status_code=status.HTTP_200_OK,
    summary="Update a discount",
    description=(
        "Updates a non-linked gym discount. If value fields changed, "
        "creates a new Stripe coupon and syncs affected memberships."
    ),
    responses={
        200: {"description": "Discount updated successfully"},
        400: {"description": "Invalid request or linked discount"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Discount not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def update_discount(
    request: DiscountUpdateRequest,
    background_tasks: BackgroundTasks,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> DiscountResponse:
    """Update an existing non-linked discount.

    Args:
        request: Discount update data.
        background_tasks: FastAPI background tasks for membership sync.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await discounts_service.update_discount(
            request,
            background_tasks,
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
            "Failed to update discount %s",
            request.discount_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update discount",
        ) from None


@discounts_router.delete(
    "/",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a discount",
    description=(
        "Soft-deletes a non-linked discount, deletes the Stripe coupon, "
        "removes it from all memberships, and syncs payments."
    ),
    responses={
        204: {"description": "Discount deleted successfully"},
        400: {"description": "Linked discount or invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Discount not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def delete_discount(
    discount_id: UUID,
    gym_id: UUID,
    background_tasks: BackgroundTasks,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> None:
    """Soft-delete a non-linked discount.

    Args:
        discount_id: The discount to delete.
        gym_id: The gym owning the discount.
        background_tasks: FastAPI background tasks for membership sync.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await discounts_service.delete_discount(
            discount_id,
            gym_id,
            background_tasks,
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
            "Failed to delete discount %s",
            discount_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete discount",
        ) from None
