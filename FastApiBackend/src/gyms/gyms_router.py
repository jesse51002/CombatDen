"""API routes for the gyms domain.

Three endpoints:

    * ``POST /api/v1/gyms/`` — create a gym + mint a Stripe Express
      account, return the hosted onboarding URL.
    * ``GET /api/v1/gyms/me/onboarding`` — refresh the caller's
      onboarding status from Stripe and return a new URL if still
      pending.
    * ``POST /api/v1/gyms/me/onboarding/link`` — cheap "mint a fresh
      hosted link" path for resume flow.

All three require a Supabase JWT (via the shared ``Auth`` service)
and all three log exceptions with ``exc_info=True`` before raising
``HTTPException``.
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
)
from src.gyms.service.gyms_service import (
    GYM_STATUS_COMPLETE,
    GYM_STATUS_DISABLED,
    GYM_STATUS_PENDING,
    GymAlreadyExistsError,
    GymsService,
)
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

# 409 detail strings — the Flutter client switches on these, so
# they are part of the public contract with the frontend.
CONFLICT_ALREADY_COMPLETE = "Gym already set up"
CONFLICT_FINISH_ONBOARDING = "Finish onboarding: GET /api/v1/gyms/me/onboarding"
CONFLICT_DISABLED = "Gym Stripe account is disabled, contact support"


def _conflict_detail_for(status_value: str) -> str:
    """Map an existing gym's status to the 409 detail string."""
    if status_value == GYM_STATUS_COMPLETE:
        return CONFLICT_ALREADY_COMPLETE
    if status_value == GYM_STATUS_PENDING:
        return CONFLICT_FINISH_ONBOARDING
    if status_value == GYM_STATUS_DISABLED:
        return CONFLICT_DISABLED
    return f"Gym already exists (status={status_value})"


# ── Create ────────────────────────────────────────────────────


@gyms_router.post(
    "/",
    response_model=GymCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a gym + begin Stripe Connect Express onboarding",
    description=(
        "Creates a gym row and its owner ``gym_employees`` record, "
        "mints a Stripe Express Connect account for the gym, and "
        "returns a short-lived (~5 minute) hosted onboarding URL. "
        "The gym row is invisible through the ``gyms`` filtered "
        "view until the Stripe account id has been attached."
    ),
    responses={
        201: {"description": "Gym + Stripe account created, onboarding pending"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        409: {"description": "User already owns a gym"},
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
    """Create a new gym and start Stripe Express onboarding.

    Raises:
        HTTPException: 400/401/409/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])
    user_email = user_payload.get("email")
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
    except GymAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_conflict_detail_for(exc.existing_status),
        ) from None
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
            detail="Stripe account created but CRM update failed",
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


# ── Onboarding status (refresh) ───────────────────────────────


@gyms_router.get(
    "/me/onboarding",
    response_model=GymOnboardingStatusResponse,
    status_code=status.HTTP_200_OK,
    summary="Refresh the caller's Stripe onboarding status",
    description=(
        "Looks up the caller's in-progress gym via ``gym_employees``, "
        "retrieves the connected account from Stripe, maps it to a "
        "``pending``/``complete``/``disabled`` status, and writes "
        "back to the CRM. If the resulting status is still "
        "``pending``, a fresh AccountLink is minted and returned so "
        "the client can re-open the hosted flow."
    ),
    responses={
        200: {"description": "Status refreshed"},
        401: {"description": "Not authenticated"},
        404: {"description": "No gym owned by this user, or Stripe account missing"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def get_onboarding_status(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymOnboardingStatusResponse:
    """Refresh and return the current Stripe onboarding status.

    Raises:
        HTTPException: 401/404/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])

    try:
        return await gyms_service.get_onboarding_status(user_id)
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
            "Stripe error while refreshing onboarding status for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to refresh onboarding status for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to refresh onboarding status",
        ) from None


# ── Fresh onboarding link (resume path) ───────────────────────


@gyms_router.post(
    "/me/onboarding/link",
    response_model=GymOnboardingLinkResponse,
    status_code=status.HTTP_200_OK,
    summary="Mint a fresh Stripe onboarding link for the caller's gym",
    description=(
        "Cheap path for the Flutter app to get a new hosted URL "
        "when the previous one expired. Only valid while the gym "
        "is in the ``pending`` state."
    ),
    responses={
        200: {"description": "New onboarding link minted"},
        401: {"description": "Not authenticated"},
        404: {"description": "No gym owned by this user"},
        409: {"description": "Gym is not in a pending state"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def new_onboarding_link(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymOnboardingLinkResponse:
    """Mint a fresh onboarding link for a pending gym.

    Raises:
        HTTPException: 401/404/409/502/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    user_id = UUID(user_payload["sub"])

    try:
        return await gyms_service.get_fresh_onboarding_link(user_id)
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
            "Stripe error while minting onboarding link for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to mint onboarding link for user_id=%s",
            user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to mint onboarding link",
        ) from None
