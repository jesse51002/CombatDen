"""API routes for the gyms domain.

Endpoints:

    * ``POST /api/v1/gyms/``            — create a gym + begin Stripe
      Connect Express onboarding.
    * ``GET /api/v1/gyms/``             — list the gyms the caller may
      administer (owner/admin), annotated with their role.
    * ``GET /api/v1/gyms/{gym_id}/onboarding`` — refresh Stripe
      onboarding status from the connected account (owner only).
    * ``POST /api/v1/gyms/{gym_id}/onboarding/link`` — mint a fresh
      hosted onboarding URL, resume flow (owner only).
    * ``PUT /api/v1/gyms/{gym_id}``     — update mutable gym fields.
"""

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
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
    GymResponse,
    GymUpdateRequest,
    GymWithRoleResponse,
)
from src.gyms.service.gyms_service import GymsService
from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
    PaymentsStripeError,
    StripeOrphanError,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

gyms_router = APIRouter(
    prefix="/api/v1/gyms",
    tags=["gyms"],
)


# ── Create ────────────────────────────────────────────────────


@gyms_router.post(
    "/",
    response_model=GymCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a gym + begin Stripe Connect Express onboarding",
    description=(
        "Creates a gym row and the calling user's owner "
        "``gym_employees`` record, mints a Stripe Connect Express "
        "account, and returns a short-lived (~5 minute) hosted "
        "onboarding URL."
    ),
    responses={
        201: {"description": "Gym + Stripe account created, onboarding pending"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def create_gym(
    request: GymCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymCreateResponse:
    """Create a new gym and start Stripe Express onboarding."""
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])
    user_email: str | None = user_payload.get("email")

    if not user_email:
        logger.error(
            "JWT payload missing email claim for user_id=%s",
            user_id,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="JWT missing email claim",
        ) from None

    try:
        return await gyms_service.create_gym(
            request=request,
            user_id=user_id,
            user_email=user_email,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except StripeOrphanError:
        logger.error(
            "Stripe account orphaned while creating gym for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Stripe account created but DB update failed",
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error while creating gym for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
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


# ── List my gyms ──────────────────────────────────────────────


@gyms_router.get(
    "/",
    response_model=list[GymWithRoleResponse],
    summary="List the gyms the caller may administer",
    description=(
        "Returns every gym the authenticated user owns or admins, "
        "each annotated with the caller's role (``employee_type``). "
        "Trainers are excluded. Returns an empty list when the user "
        "administers no gyms."
    ),
    responses={
        200: {"description": "Gyms retrieved (possibly empty)"},
        401: {"description": "Not authenticated"},
    },
)
@inject
async def list_my_gyms(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> list[GymWithRoleResponse]:
    """Return the gyms the caller owns or admins."""
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])

    try:
        return await gyms_service.list_gyms_for_user(user_id)
    except Exception:
        logger.error(
            "Failed to list gyms for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve gyms",
        ) from None


# ── Onboarding status (refresh) ───────────────────────────────


@gyms_router.get(
    "/{gym_id}/onboarding",
    response_model=GymOnboardingStatusResponse,
    status_code=status.HTTP_200_OK,
    summary="Refresh a gym's Stripe onboarding status (owner only)",
    description=(
        "Retrieves the gym's connected account from Stripe, maps it "
        "to a ``pending``/``complete`` status, and writes back to the "
        "DB. If the resulting status is still ``pending``, a fresh "
        "AccountLink is minted and returned so the client can "
        "re-open the hosted flow. The caller must be the gym's owner."
    ),
    responses={
        200: {"description": "Status refreshed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not the owner of this gym"},
        404: {"description": "Gym not found, or Stripe account missing"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def get_onboarding_status(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymOnboardingStatusResponse:
    """Refresh and return the current Stripe onboarding status."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_owner(gym_id, user_payload)

    try:
        return await gyms_service.get_onboarding_status(gym_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except PaymentsResourceNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error while refreshing onboarding status for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to refresh onboarding status for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to refresh onboarding status",
        ) from None


# ── Fresh onboarding link (resume path) ───────────────────────


@gyms_router.post(
    "/{gym_id}/onboarding/link",
    response_model=GymOnboardingLinkResponse,
    status_code=status.HTTP_200_OK,
    summary="Mint a fresh Stripe onboarding link for a gym (owner only)",
    description=(
        "Cheap path for the Flutter app to get a new hosted URL "
        "when the previous one expired. Only valid while the gym "
        "is in the ``pending`` state. The caller must be the gym's "
        "owner."
    ),
    responses={
        200: {"description": "New onboarding link minted"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not the owner of this gym"},
        404: {"description": "Gym not found or has no Stripe account"},
        409: {"description": "Gym is not in a pending state"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def new_onboarding_link(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymOnboardingLinkResponse:
    """Mint a fresh onboarding link for a pending gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_owner(gym_id, user_payload)

    try:
        return await gyms_service.get_fresh_onboarding_link(gym_id)
    except ValueError as exc:
        msg = str(exc)
        if "No gym" in msg or "no Stripe account" in msg:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=msg,
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error while minting onboarding link for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to mint onboarding link for gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to mint onboarding link",
        ) from None


# ── Update ────────────────────────────────────────────────────


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
