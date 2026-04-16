"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.schema.member_details_schema import (
    MemberDetailResponse,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembersListTotalCounts,
)
from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementLinkRequest,
    MembersManagementResponse,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)
from src.members.service.member_details_service import (
    MemberService,
)
from src.members.service.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.members.service.members_management_service import (
    MembersManagementService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

members_router = APIRouter(
    prefix="/api/v1/members",
    tags=["members"],
)


@members_router.get(
    "/member_details",
    response_model=MemberDetailResponse,
    summary="Get member details",
    description=(
        "Returns full details for a single member including "
        "all memberships, discounts, payment history, and rewards."
    ),
    responses={
        200: {"description": "Member details retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_details(
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    member_service: MemberService = Depends(Provide[DependencyInjector.member_service]),
) -> MemberDetailResponse:
    """Get full details for a single member.

    Args:
        crm_user_id: The member's CRM user ID.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        member_service: Injected member service.

    Returns:
        MemberDetailResponse with all memberships and
        supplementary data.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 404 if not found,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        response = await member_service.get_member_details(
            crm_user_id=crm_user_id,
        )
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to get member details: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve member details",
        ) from None

    return response


@members_router.post(
    "/crm_members_list",
    response_model=CrmMembersListResponse,
    summary="Get CRM members list",
    description=(
        "Returns a filtered, sorted, paginated list of gym "
        "members for the CRM members list screen."
    ),
    responses={
        200: {"description": "Members list retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": ("Not authorized to access this gym")},
    },
)
@inject
async def crm_members_list(
    request: CrmMembersListRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crm_members_list_service: CrmMembersListService = Depends(
        Provide[DependencyInjector.crm_members_list_service]
    ),
) -> CrmMembersListResponse:
    """Get filtered, paginated members list for the CRM screen.

    Args:
        request: Members list request with view, filters,
            and pagination params.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        crm_members_list_service: Injected members list service.

    Returns:
        CrmMembersListResponse with pre-formatted rows.

    Raises:
        HTTPException: 401 if not authenticated,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await crm_members_list_service.get_crm_members_list(request)
    except Exception:
        logger.error(
            "Failed to get members list: gym_id=%s, view=%s",
            request.gym_id,
            request.requested_view,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve members list",
        ) from None


@members_router.get(
    "/crm_total_counts",
    response_model=MembersListTotalCounts,
    summary="Get CRM member total counts",
    description=("Returns unfiltered member counts per status for the CRM members list subtitle."),
    responses={
        200: {"description": "Total counts retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": ("Not authorized to access this gym")},
    },
)
@inject
async def crm_total_counts(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    total_counts_service: CrmTotalCountsService = Depends(
        Provide[DependencyInjector.crm_total_counts_service]
    ),
) -> MembersListTotalCounts:
    """Get unfiltered member counts per status.

    Args:
        gym_id: The gym to count members for.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        total_counts_service: Injected total counts service.

    Returns:
        MembersListTotalCounts with active, trial,
        frozen, overdue.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await total_counts_service.get_total_counts(gym_id)
    except Exception:
        logger.error(
            "Failed to get total counts: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve total counts",
        ) from None


# ── Member Management ────────────────────────────────────────────


@members_router.post(
    "/",
    response_model=MembersManagementResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new member",
    description=(
        "Creates a new gym member. If a payment_method_id is "
        "provided, a Stripe customer is also created."
    ),
    responses={
        201: {"description": "Member created successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_member(
    request: MembersManagementCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Create a new gym member.

    Args:
        request: Member creation data with optional card info.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with the created member.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await management_service.create_member(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error creating member: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create member: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create member",
        ) from None


@members_router.put(
    "/{crm_user_id}",
    response_model=MembersManagementResponse,
    summary="Update member personal info",
    description=("Updates a member's personal information. Does not affect card or Stripe data."),
    responses={
        200: {"description": "Member updated successfully"},
        400: {"description": "Attempted to update immutable columns"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def update_member(
    crm_user_id: UUID,
    request: MembersManagementUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Update a member's personal information.

    Args:
        crm_user_id: The member to update.
        request: Fields to update (all optional).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with the updated member.

    Raises:
        HTTPException: 400 if no fields provided,
            401 if not authenticated, 403 if not authorized,
            404 if member not found, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.update_member(
            crm_user_id,
            request,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
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
            "Failed to update member: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update member",
        ) from None


@members_router.put(
    "/{crm_user_id}/card",
    response_model=MembersManagementResponse,
    summary="Update member payment card",
    description=(
        "Updates a member's payment card. Overwrites card data "
        "in the database and updates Stripe. Creates a Stripe "
        "customer if the member doesn't have one yet."
    ),
    responses={
        200: {"description": "Card updated successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def update_member_card(
    crm_user_id: UUID,
    request: MembersManagementUpdateCardRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Update a member's payment card in DB and Stripe.

    Args:
        crm_user_id: The member to update.
        request: The new payment method ID.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with updated card details.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 404 if member not found,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.update_card(
            crm_user_id,
            request,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg,
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error updating card: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to update card: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update card",
        ) from None


@members_router.delete(
    "/{crm_user_id}/payment",
    response_model=MembersManagementResponse,
    summary="Unlink member payment",
    description=(
        "Removes a member's payment card from the CRM and "
        "immediately cancels all active recurring memberships. "
        "The Stripe customer link is preserved."
    ),
    responses={
        200: {"description": "Payment unlinked successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def unlink_member_payment(
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Unlink a member's payment card and cancel recurring memberships.

    Args:
        crm_user_id: The member to unlink.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with NULLed card fields.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized, 404 if member not found,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.unlink_payment(crm_user_id)
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
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
            "Failed to unlink payment: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unlink payment",
        ) from None


@members_router.put(
    "/{crm_user_id}/link",
    response_model=MembersManagementResponse,
    summary="Link member to a parent account",
    description=(
        "Links an existing member to a paying parent account. "
        "The child must have zero active recurring memberships. "
        "Clears any stripe subscription, card, and freeze state "
        "on the child (required by the linked_account_no_stripe "
        "DB constraint) and re-syncs the parent's subscription "
        "so linked-discount assignments are recalculated. No "
        "proration or mid-cycle charges are issued."
    ),
    responses={
        200: {"description": "Member linked successfully"},
        400: {
            "description": (
                "Child is already linked, has active recurring "
                "memberships, or the relationship is invalid"
            )
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def link_member_account(
    crm_user_id: UUID,
    request: MembersManagementLinkRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Link a member to a paying parent account.

    Args:
        crm_user_id: The child member to link.
        request: Body containing the parent_crm_user_id.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with updated linked-account state.

    Raises:
        HTTPException: 400 on validation errors, 401 if not
            authenticated, 403 if not authorized, 404 if the
            member is not found, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.link_account(
            crm_user_id,
            request.parent_crm_user_id,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg,
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error linking member: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to link member: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to link member",
        ) from None


@members_router.delete(
    "/{crm_user_id}/link",
    response_model=MembersManagementResponse,
    summary="Unlink member from a parent account",
    description=(
        "Unlinks a member from their paying parent account. "
        "Clears account_linked_to_id and linked_discount_id on "
        "the child, then re-syncs the old parent's subscription "
        "so linked-discount assignments are recalculated for "
        "the remaining children. The child must have zero "
        "active recurring memberships. No proration or "
        "mid-cycle charges are issued."
    ),
    responses={
        200: {"description": "Member unlinked successfully"},
        400: {"description": ("Child is not linked or has active recurring memberships")},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def unlink_member_account(
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersManagementResponse:
    """Unlink a member from their paying parent account.

    Args:
        crm_user_id: The child member to unlink.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.

    Returns:
        MembersManagementResponse with account_linked_to_id cleared.

    Raises:
        HTTPException: 400 on validation errors, 401 if not
            authenticated, 403 if not authorized, 404 if the
            member is not found, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.unlink_account(crm_user_id)
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=error_msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg,
        ) from None
    except PaymentsStripeError as exc:
        logger.error(
            "Stripe error unlinking member: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to unlink member: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unlink member",
        ) from None


@members_router.get(
    "/{crm_user_id}/invoices",
    response_model=list[PaymentsInvoiceResponse],
    summary="List member invoices",
    description="Returns a paginated list of Stripe invoices for a member.",
    responses={
        200: {"description": "Invoices retrieved successfully"},
        400: {"description": "Member has no Stripe customer"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def list_member_invoices(
    crm_user_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
    limit: int = 100,
    starting_after: str | None = None,
) -> list[PaymentsInvoiceResponse]:
    """List Stripe invoices for a member.

    Args:
        crm_user_id: The member whose invoices to list.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        management_service: Injected management service.
        limit: Max invoices to return (default 10).
        starting_after: Cursor for pagination (invoice ID).

    Returns:
        List of PaymentsInvoiceResponse from Stripe.

    Raises:
        HTTPException: 400 if member has no Stripe customer,
            401 if not authenticated, 403 if not authorized,
            404 if member not found, 500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(crm_user_id, user_payload)

    try:
        return await management_service.list_invoices(
            crm_user_id,
            limit=limit,
            starting_after=starting_after,
        )
    except ValueError as exc:
        error_msg = str(exc)
        if "not found" in error_msg:
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
            "Failed to list invoices: crm_user_id=%s",
            crm_user_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list invoices",
        ) from None
