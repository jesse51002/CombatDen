"""API routes for the waivers domain.

Waiver catalog CRUD, version history, and read-only signature tracking
(per-waiver roster + per-member status). Editing a waiver's body publishes a new
immutable version; signatures bind to the exact version signed.

Signature CAPTURE has ONE path: the standalone, staff-authenticated
``POST /{waiver_id}/signatures`` endpoint here (any member signs any waiver,
version-locked on the echoed version). The authorized-payer link flow
(memberships) does NOT sign — the payer signs the gym's default waiver through
THIS endpoint first, then the link references that signature_id (signing and
authorizing are decoupled).
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.shared.request_audit import capture_ip_address, capture_user_agent
from src.waivers.schema.waivers_schema import (
    MemberWaiverStatusRow,
    WaiverCreateRequest,
    WaiverResponse,
    WaiverSignatoryRow,
    WaiverSignatureResponse,
    WaiverSignRequest,
    WaiverUpdateRequest,
    WaiverVersionResponse,
)
from src.waivers.service.waivers_service import WaiversService

logger = logging.getLogger(__name__)

waivers_router = APIRouter(
    prefix="/api/v1/waivers",
    tags=["waivers"],
)


@waivers_router.get(
    "/",
    response_model=list[WaiverResponse],
    status_code=status.HTTP_200_OK,
    summary="List waivers for a gym",
    description=(
        "Lists non-deleted waivers for the gym, each with its current version "
        "number and the count of members who signed the current version."
    ),
    responses={
        200: {"description": "Waivers listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_waivers(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> list[WaiverResponse]:
    """List waivers for a gym.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await waivers_service.list_waivers(gym_id)
    except Exception:
        logger.error("Failed to list waivers for gym_id=%s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list waivers",
        ) from None


@waivers_router.post(
    "/",
    response_model=WaiverResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a waiver",
    description="Creates a waiver and publishes its first version.",
    responses={
        201: {"description": "Waiver created successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_waiver(
    request: WaiverCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> WaiverResponse:
    """Create a waiver.

    Raises:
        HTTPException: 400/401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await waivers_service.create_waiver(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create waiver for gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create waiver",
        ) from None


@waivers_router.put(
    "/",
    response_model=WaiverResponse,
    status_code=status.HTTP_200_OK,
    summary="Update a waiver",
    description=(
        "Renames a waiver and/or publishes a new version of its text. Editing "
        "the body publishes a new immutable version; an unchanged body is a "
        "no-op. Members must re-sign a newly published version."
    ),
    responses={
        200: {"description": "Waiver updated successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Waiver not found"},
    },
)
@inject
async def update_waiver(
    request: WaiverUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> WaiverResponse:
    """Update a waiver.

    Raises:
        HTTPException: 400/401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await waivers_service.update_waiver(request)
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
        logger.error("Failed to update waiver %s", request.waiver_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update waiver",
        ) from None


@waivers_router.delete(
    "/",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Archive a waiver",
    description=(
        "Archives a waiver (soft-delete). Its versions and signatures are "
        "retained for the legal record."
    ),
    responses={
        204: {"description": "Waiver archived successfully"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Waiver not found"},
    },
)
@inject
async def delete_waiver(
    waiver_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> None:
    """Archive a waiver.

    Raises:
        HTTPException: 400/401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await waivers_service.delete_waiver(waiver_id, gym_id)
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
        logger.error("Failed to delete waiver %s", waiver_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete waiver",
        ) from None


@waivers_router.get(
    "/signatures/by-member/{member_id}",
    response_model=list[MemberWaiverStatusRow],
    status_code=status.HTTP_200_OK,
    summary="List a member's waiver status",
    description=(
        "Lists every non-deleted gym waiver with this member's latest sign "
        "status for each (for the member-detail Waivers section)."
    ),
    responses={
        200: {"description": "Member waiver status listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_member_waiver_status(
    member_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> list[MemberWaiverStatusRow]:
    """List a member's waiver status across the gym's waivers.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await waivers_service.list_member_status(member_id, gym_id)
    except Exception:
        logger.error(
            "Failed to list waiver status for member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list member waiver status",
        ) from None


@waivers_router.get(
    "/{waiver_id}/versions",
    response_model=list[WaiverVersionResponse],
    status_code=status.HTTP_200_OK,
    summary="List a waiver's versions",
    description=(
        "Lists a waiver's immutable version history, newest first, each with "
        "the count of members who signed that exact version."
    ),
    responses={
        200: {"description": "Versions listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_waiver_versions(
    waiver_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> list[WaiverVersionResponse]:
    """List a waiver's version history.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await waivers_service.list_versions(waiver_id, gym_id)
    except Exception:
        logger.error(
            "Failed to list versions for waiver %s",
            waiver_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list waiver versions",
        ) from None


@waivers_router.get(
    "/{waiver_id}/signatures",
    response_model=list[WaiverSignatoryRow],
    status_code=status.HTTP_200_OK,
    summary="List a waiver's signature roster",
    description=(
        "Lists every gym member and their latest sign status for this waiver — "
        "signed?, which version, when, and whether it is the current version."
    ),
    responses={
        200: {"description": "Roster listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_waiver_signatories(
    waiver_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> list[WaiverSignatoryRow]:
    """List a waiver's signature roster.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await waivers_service.list_signatories(waiver_id, gym_id)
    except Exception:
        logger.error(
            "Failed to list signatories for waiver %s",
            waiver_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list waiver signatories",
        ) from None


@waivers_router.post(
    "/{waiver_id}/signatures",
    response_model=WaiverSignatureResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record a waiver signature",
    description=(
        "Records one member's e-signature on a waiver (staff-driven). The client "
        "echoes the waiver_version_id it displayed; the backend version-locks on "
        "the waiver's current version (409 if it changed) and captures the "
        "signer's IP, user-agent, and the staff operator server-side."
    ),
    responses={
        201: {"description": "Signature recorded successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Waiver or member not found"},
        409: {"description": "Waiver was updated — reload and re-sign"},
    },
)
@inject
async def sign_waiver(
    waiver_id: UUID,
    request: WaiverSignRequest,
    http_request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> WaiverSignatureResponse:
    """Record a member's signature on a waiver.

    Raises:
        HTTPException: 400/401/403/404/409/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    # get_employee_id both authorizes (403 if not staff of the gym) and resolves
    # the operator/witness to stamp on the signature.
    operator_employee_id = await auth.get_employee_id(
        request.gym_id, user_payload
    )

    try:
        return await waivers_service.sign_waiver(
            gym_id=request.gym_id,
            member_id=request.member_id,
            waiver_id=waiver_id,
            waiver_version_id=request.waiver_version_id,
            signer_name=request.signer_name,
            consent_acknowledged=request.consent_acknowledged,
            ip_address=capture_ip_address(http_request),
            user_agent=capture_user_agent(http_request),
            operator_employee_id=operator_employee_id,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "reload" in error_msg.lower():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=error_msg,
            ) from None
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
            "Failed to record signature for waiver %s",
            waiver_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record waiver signature",
        ) from None


@waivers_router.get(
    "/{waiver_id}",
    response_model=WaiverResponse,
    status_code=status.HTTP_200_OK,
    summary="Get a waiver",
    description="Fetches a single waiver with its current version body.",
    responses={
        200: {"description": "Waiver fetched successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Waiver not found"},
    },
)
@inject
async def get_waiver(
    waiver_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(Provide[DependencyInjector.waivers_service]),
) -> WaiverResponse:
    """Get a single waiver.

    Raises:
        HTTPException: 401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await waivers_service.get_waiver(waiver_id, gym_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error("Failed to get waiver %s", waiver_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get waiver",
        ) from None
