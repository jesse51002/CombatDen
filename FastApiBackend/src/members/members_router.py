"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.schema.members_billing_schema import (
    MemberBillingDetailResponse,
    MembersBillingLinkCheckResponse,
    MembersBillingLinkRequest,
    MembersBillingProfileResponse,
    MembersBillingUpdateCardRequest,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembersListTotalCounts,
)
from src.members.schema.members_schema import (
    MemberCreateRequest,
    MemberResponse,
    MemberUpdateRequest,
)
from src.members.service.member_details.members_billing_detail_service import (
    MembersBillingDetailService,
)
from src.members.service.crm_member_services.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.crm_member_services.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.members.service.management.members_management_service import (
    MembersManagementService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
    PaymentsInvoiceResponse,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

members_router = APIRouter(
    prefix="/api/v1/members",
    tags=["members"],
)


@members_router.post(
    "/",
    response_model=MembersBillingProfileResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a member (provisions a Stripe customer)",
    responses={
        201: {"description": "Member created with a Stripe customer"},
        400: {"description": "Invalid request, or gym has no Stripe account"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_member(
    request: MemberCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingProfileResponse:
    """Create a member and provision its Stripe customer. Gym staff only.

    Every member is created with a Stripe customer. The gym must have a
    Stripe Connect account; otherwise the request is rejected (400) and no
    member row is written.
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
    except Exception:
        logger.error(
            "Failed to create member for gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create member",
        ) from None


@members_router.put(
    "/{member_id}",
    response_model=MemberResponse,
    summary="Update a member",
    responses={
        200: {"description": "Member updated"},
        400: {"description": "Invalid update"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def update_member(
    member_id: UUID,
    request: MemberUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MemberResponse:
    """Update a member's mutable fields."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.update_member(member_id, request.data)
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
            "Failed to update member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update member",
        ) from None


@members_router.post(
    "/list",
    response_model=CrmMembersListResponse,
    summary="List members for a gym (CRM members list)",
    description=(
        "Returns a filtered, sorted, paginated list of gym members "
        "for the CRM members list screen. The view (all / trial / "
        "frozen / overdue) plus filters and pagination are resolved "
        "and the rows are pre-formatted per view. Membership status is "
        "derived from member_memberships (member_memberships_status), "
        "not from a member_status column."
    ),
    responses={
        200: {"description": "Members list retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_members(
    request: CrmMembersListRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crm_members_list_service: CrmMembersListService = Depends(
        Provide[DependencyInjector.crm_members_list_service]
    ),
) -> CrmMembersListResponse:
    """Filtered, sorted, paginated CRM members list."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await crm_members_list_service.get_crm_members_list(request)
    except Exception:
        logger.error(
            "Failed to list members: gym_id=%s, view=%s",
            request.gym_id,
            request.requested_view,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve members",
        ) from None


@members_router.get(
    "/counts",
    response_model=MembersListTotalCounts,
    summary="Unfiltered member counts per status",
    description=(
        "Returns unfiltered member counts per status (active / trial / "
        "frozen / overdue) for the CRM members list subtitle. Counts are "
        "membership-derived from member_memberships_status."
    ),
    responses={
        200: {"description": "Counts retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def total_counts(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    total_counts_service: CrmTotalCountsService = Depends(
        Provide[DependencyInjector.crm_total_counts_service]
    ),
) -> MembersListTotalCounts:
    """Unfiltered membership-derived counts per status for a gym."""
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
            detail="Failed to retrieve counts",
        ) from None


@members_router.get(
    "/{member_id}",
    response_model=MemberBillingDetailResponse,
    summary="Get member detail",
    description=(
        "Full CRM member detail for the Specific Member screen: all "
        "memberships (grouped by plan), linked family accounts, payment "
        "history, redeemed rewards, and the card on file. Membership "
        "status is derived from member_memberships, so a member with no "
        "membership resolves cleanly without error."
    ),
    responses={
        200: {"description": "Member detail retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_detail(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    billing_detail_service: MembersBillingDetailService = Depends(
        Provide[DependencyInjector.members_billing_detail_service]
    ),
) -> MemberBillingDetailResponse:
    """Full membership-derived member detail."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await billing_detail_service.get_member_billing_detail(member_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to get member detail: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve member detail",
        ) from None


# ── CRM Billing Endpoints ────────────────────────────────────────


@members_router.get(
    "/{member_id}/billing",
    response_model=MemberBillingDetailResponse,
    summary="Get full member billing detail",
    description=(
        "Returns full CRM member detail including all memberships, "
        "linked accounts, payment history, and card on file."
    ),
    responses={
        200: {"description": "Billing detail retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_billing_detail(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    billing_detail_service: MembersBillingDetailService = Depends(
        Provide[DependencyInjector.members_billing_detail_service]
    ),
) -> MemberBillingDetailResponse:
    """Full CRM billing detail for a member."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await billing_detail_service.get_member_billing_detail(member_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to get member billing detail: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve member billing detail",
        ) from None


@members_router.put(
    "/{member_id}/card",
    response_model=MembersBillingProfileResponse,
    summary="Update member payment card",
    description=(
        "Updates a member's payment card. Overwrites card data in the "
        "database and updates Stripe. Creates a Stripe customer if the "
        "member doesn't have one yet."
    ),
    responses={
        200: {"description": "Card updated successfully"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def update_member_card(
    member_id: UUID,
    request: MembersBillingUpdateCardRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingProfileResponse:
    """Update a member's payment card in DB and Stripe."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.update_card(member_id, request)
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
        logger.error(
            "Stripe error updating card: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to update card: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update card",
        ) from None


@members_router.delete(
    "/{member_id}/payment",
    response_model=MembersBillingProfileResponse,
    summary="Unlink member payment",
    description=(
        "Removes a member's payment card from the CRM and immediately cancels "
        "all active recurring memberships. The Stripe customer link is preserved."
    ),
    responses={
        200: {"description": "Payment unlinked successfully"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def unlink_member_payment(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingProfileResponse:
    """Unlink a member's payment card and cancel recurring memberships."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.unlink_payment(member_id)
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
            "Failed to unlink payment: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unlink payment",
        ) from None


@members_router.put(
    "/{member_id}/link",
    response_model=MembersBillingProfileResponse,
    summary="Link member to a parent account",
    description=(
        "Links an existing member to a paying parent account. "
        "The child must have zero active recurring memberships. "
        "Clears any stripe subscription, card, and freeze state on the child "
        "(required by the linked_account_no_stripe DB constraint) and re-syncs "
        "the parent's subscription so linked-discount assignments are "
        "recalculated. No proration or mid-cycle charges are issued."
    ),
    responses={
        200: {"description": "Member linked successfully"},
        400: {"description": "Child is already linked or has active recurring memberships"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def link_member_account(
    member_id: UUID,
    request: MembersBillingLinkRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingProfileResponse:
    """Link a member to a paying parent account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.link_account(
            member_id,
            request.parent_member_id,
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
        logger.error(
            "Stripe error linking member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to link member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to link member",
        ) from None


@members_router.delete(
    "/{member_id}/link",
    response_model=MembersBillingProfileResponse,
    summary="Unlink member from a parent account",
    description=(
        "Unlinks a member from their paying parent account. "
        "Clears account_linked_to_id and linked_discount_id on the child, "
        "then re-syncs the old parent's subscription so linked-discount "
        "assignments are recalculated for the remaining children. "
        "The child must have zero active recurring memberships. "
        "No proration or mid-cycle charges are issued."
    ),
    responses={
        200: {"description": "Member unlinked successfully"},
        400: {"description": "Child is not linked or has active recurring memberships"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def unlink_member_account(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingProfileResponse:
    """Unlink a member from their paying parent account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.unlink_account(member_id)
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
        logger.error(
            "Stripe error unlinking member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to unlink member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unlink member",
        ) from None


@members_router.post(
    "/{member_id}/link/check",
    response_model=MembersBillingLinkCheckResponse,
    summary="Check if a member can be linked to a parent account",
    description=(
        "Read-only validation. Returns can_link + a pre-formatted, "
        "user-facing error string when linking is blocked."
    ),
    responses={
        200: {"description": "Check completed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def check_link_member_account(
    member_id: UUID,
    request: MembersBillingLinkRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MembersBillingLinkCheckResponse:
    """Check whether a member can be linked to a parent account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.check_link_account(
            member_id,
            request.parent_member_id,
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
            "Failed to check member link: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to check member link",
        ) from None


@members_router.post(
    "/{member_id}/link/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview linking a member to a parent account",
    description=(
        "Dry-run of the link endpoint: runs every validation and returns the "
        "Stripe invoice preview for the parent's resulting subscription. "
        "Returns null if the parent has no recurring subscription to preview."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        400: {"description": "Child is already linked or has active recurring memberships"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def preview_link_member_account(
    member_id: UUID,
    request: MembersBillingLinkRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview what linking a member to a parent would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.preview_link_account(
            member_id,
            request.parent_member_id,
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
        logger.error(
            "Stripe error previewing link: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to preview link member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview member link",
        ) from None


@members_router.post(
    "/{member_id}/unlink/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview unlinking a member from a parent account",
    description=(
        "Dry-run of the unlink endpoint: runs every validation and returns "
        "the Stripe invoice preview for the old parent's resulting subscription. "
        "Returns null if the old parent has no recurring subscription to preview."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        400: {"description": "Child is not linked or has active recurring memberships"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def preview_unlink_member_account(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview what unlinking a member from a parent would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.preview_unlink_account(member_id)
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
        logger.error(
            "Stripe error previewing unlink: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to preview unlink member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview member unlink",
        ) from None


@members_router.get(
    "/{member_id}/invoices",
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
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
    limit: int = 100,
    starting_after: str | None = None,
) -> list[PaymentsInvoiceResponse]:
    """List Stripe invoices for a member."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await management_service.list_invoices(
            member_id,
            limit=limit,
            starting_after=starting_after,
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
            "Failed to list invoices: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list invoices",
        ) from None
