"""API routes for the discounts domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountResponse,
    DiscountUpdateRequest,
)
from src.discounts.service.discounts.discounts_service import DiscountsService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

discounts_router = APIRouter(
    prefix="/api/v1/discounts",
    tags=["discounts"],
)


@discounts_router.get(
    "/",
    response_model=list[DiscountResponse],
    status_code=status.HTTP_200_OK,
    summary="List preset discounts for a gym",
    description=(
        "Lists non-deleted preset discounts for the gym. Custom and linked discounts are excluded."
    ),
    responses={
        200: {"description": "Discounts listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_discounts(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> list[DiscountResponse]:
    """List preset discounts for a gym.

    Args:
        gym_id: The gym whose discounts to list.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await discounts_service.list_discounts(gym_id)
    except Exception:
        logger.error(
            "Failed to list discounts for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list discounts",
        ) from None


@discounts_router.post(
    "/",
    response_model=DiscountResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a discount preset",
    description="Creates a coupon-free gym discount preset (plain config).",
    responses={
        201: {"description": "Discount created successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_discount(
    request: DiscountCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> DiscountResponse:
    """Create a new gym discount preset.

    Args:
        request: Discount preset creation data.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/500 on respective errors.
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
    summary="Update a discount preset",
    description=(
        "Edits a gym discount preset's intent and lifetime spec. Edits affect "
        "only future applications; existing applied-discount snapshots are "
        "untouched."
    ),
    responses={
        200: {"description": "Discount updated successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Discount not found"},
    },
)
@inject
async def update_discount(
    request: DiscountUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> DiscountResponse:
    """Update an existing discount preset.

    Args:
        request: Discount update data.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await discounts_service.update_discount(request)
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
    summary="Archive a discount preset",
    description=(
        "Archives a discount preset (soft-delete). Existing applied-discount "
        "snapshots keep their frozen copy, so member bills are unchanged."
    ),
    responses={
        204: {"description": "Discount archived successfully"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Discount not found"},
    },
)
@inject
async def delete_discount(
    discount_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    discounts_service: DiscountsService = Depends(Provide[DependencyInjector.discounts_service]),
) -> None:
    """Archive a discount preset.

    Args:
        discount_id: The discount to archive.
        gym_id: The gym owning the discount (authorization scope).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        discounts_service: Injected discounts service.

    Raises:
        HTTPException: 400/401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await discounts_service.delete_discount(discount_id)
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
            "Failed to delete discount %s",
            discount_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete discount",
        ) from None
