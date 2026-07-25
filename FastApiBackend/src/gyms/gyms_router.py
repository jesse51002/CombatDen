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
    * ``PUT /api/v1/gyms/{gym_id}/theme`` — save the gym's chosen
      ThemeService design id (branding).
    * ``PUT /api/v1/gyms/{gym_id}/employees/me/theme`` — save the
      caller's CRM theme preference (system/light/dark).
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.gyms.schema.gyms_schema import (
    EmployeeThemeResponse,
    EmployeeThemeUpdateRequest,
    GymCreateRequest,
    GymCreateResponse,
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
    GymResponse,
    GymThemeResponse,
    GymThemeUpdateRequest,
    GymUpdateRequest,
    GymWithRoleResponse,
)
from src.gyms.service.gyms_service import GymsService
from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
    PaymentsStripeError,
    StripeOrphanError,
)
from src.shared.auth import ALL_EMPLOYEES, Auth, security

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
        "onboarding URL. The caller's email must back a CONFIRMED "
        "Supabase auth account."
    ),
    responses={
        201: {"description": "Gym + Stripe account created, onboarding pending"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated / no email claim"},
        403: {"description": "Email address is not verified"},
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
    # The caller has no gym_employees row yet, so no role check can carry
    # the verified-account predicate for them — prove it directly, or an
    # unverified signup could mint a gym as any address it liked.
    user_email = await auth.verify_verified_account(user_payload)

    try:
        return await gyms_service.create_gym(
            request=request,
            user_email=user_email,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except StripeOrphanError:
        logger.error(
            "Stripe account orphaned while creating gym for email=%s",
            user_email,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Stripe account created but DB update failed",
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error while creating gym for email=%s",
            user_email,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create gym for email=%s",
            user_email,
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
    summary="List the gyms the caller is an employee of",
    description=(
        "Returns every gym the authenticated user is an employee of "
        "(any role), each annotated with the caller's role "
        "(``employee_type``). Returns an empty list when the caller is "
        "an employee of no gyms."
    ),
    responses={
        200: {"description": "Gyms retrieved (possibly empty)"},
        401: {"description": "Not authenticated / no email claim"},
        403: {"description": "Email address is not verified"},
    },
)
@inject
async def list_my_gyms(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> list[GymWithRoleResponse]:
    """Return the gyms the caller is an employee of."""
    user_payload = auth.get_current_user(credentials)
    # No prior gate on this route (it is what DISCOVERS the caller's gyms),
    # so prove the account is confirmed here: 401 without an email claim,
    # 403 when the address backs no verified account. The SQL carries the
    # same predicate, so an unverified caller can never see a gym either way.
    user_email = await auth.verify_verified_account(user_payload)
    caller_id = auth.require_sub(user_payload)

    try:
        return await gyms_service.list_gyms_for_user(user_email, caller_id)
    except Exception:
        logger.error(
            "Failed to list gyms for email=%s",
            user_email,
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
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
    description=(
        "Updates the gym name, description, street address, timezone, "
        "sub-rank style (``sub_rank_type``), or logo. ``logo_url`` and "
        "``address`` may be explicitly set to ``null`` to clear them."
    ),
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
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

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


# ── Gym theme (branding design) ───────────────────────────────


@gyms_router.put(
    "/{gym_id}/theme",
    response_model=GymThemeResponse,
    summary="Save a gym's ThemeService design id",
    description=(
        "Persists the gym's chosen ThemeService design id "
        "(``gyms.theme_design_id``) — the branding shown in the "
        "gym's member app. ThemeService remains a separate service; "
        "this only stores the selected design's id."
    ),
    responses={
        200: {"description": "Theme design saved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
        404: {"description": "Gym not found"},
    },
)
@inject
async def update_gym_theme(
    gym_id: UUID,
    request: GymThemeUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> GymThemeResponse:
    """Save the gym's chosen ThemeService design id."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        return await gyms_service.update_gym_theme(
            gym_id=gym_id,
            theme_design_id=request.data.theme_design_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to update gym theme: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update gym theme",
        ) from None


# ── Employee theme preference ─────────────────────────────────


@gyms_router.put(
    "/{gym_id}/employees/me/theme",
    response_model=EmployeeThemeResponse,
    summary="Save the caller's CRM theme preference for a gym",
    description=(
        "Persists the calling employee's admin-app appearance choice "
        "(system / light / dark) on their ``gym_employees`` row for "
        "this gym. Rehydrated at login from ``GET /api/v1/gyms/``."
    ),
    responses={
        200: {"description": "Theme saved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
        404: {"description": "Employee not found for this gym"},
    },
)
@inject
async def update_my_theme(
    gym_id: UUID,
    request: EmployeeThemeUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    gyms_service: GymsService = Depends(Provide[DependencyInjector.gyms_service]),
) -> EmployeeThemeResponse:
    """Save the caller's CRM theme preference for this gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, ALL_EMPLOYEES)
    # verify_roles already proved the account is confirmed and holds a live
    # employee row at this gym, so the claim is trustworthy here — read it
    # directly rather than paying a second identity round-trip.
    user_email = auth.require_email(user_payload)

    try:
        return await gyms_service.update_employee_theme(
            gym_id=gym_id,
            user_email=user_email,
            theme_preference=request.data.theme_preference,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to update theme: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update theme preference",
        ) from None
