"""API routes for the members domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.members.schema.members_billing_schema import (
    BillingPaymentRecord,
    MemberBillingDetailResponse,
    MemberPaymentMethodStatusResponse,
    MembersBillingProfileResponse,
    MembersBillingUpdateCardRequest,
    PointsAdjustRequest,
    PointsAdjustResponse,
)
from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembersListTotalCounts,
)
from src.members.schema.members_schema import (
    DuplicateMemberConflict,
    MemberCreateRequest,
    MemberResponse,
    MemberUpdateRequest,
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
from src.members.service.member_details.members_billing_detail_service import (
    MembersBillingDetailService,
)
from src.members.service.member_payments_service import (
    MembersPaymentsService,
)
from src.memberships.memberships_exceptions import PartialCancelError
from src.memberships.memberships_schema import (
    MemberMembershipsCancelResponse,
    MembersBillingLinkCheckRequest,
    MembersBillingLinkCheckResponse,
    MembersBillingLinkRequest,
    MembersBillingRemoveAuthorizationPreviewRequest,
    MembersBillingRemoveAuthorizationRequest,
    PayerInvoiceChange,
)
from src.memberships.service.memberships_service import (
    MemberMembershipsService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
    PreviewInvoice,
)
from src.shared.auth import OWNER_ADMIN, STAFF, Auth, security
from src.shared.request_audit import capture_ip_address, capture_user_agent
from src.waivers.schema.waivers_schema import (
    AuthorizedPayerWaiverResponse,
)
from src.waivers.service.waivers_service import (
    WaiversService,
)

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
        409: {
            "model": DuplicateMemberConflict,
            "description": (
                "A same-identity member already exists at this gym (same "
                "name + email). The detail is "
                '{"code": "duplicate_member", "matches": [...]} listing the '
                "candidate rows; re-send with allow_duplicate=true to create "
                "anyway. Only fires when the request has an email."
            ),
        },
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

    When the request has an email and ``allow_duplicate`` is not set, a
    same-identity member already at the gym (same name + email, normalized)
    is rejected with 409 and the candidate rows before anything is written;
    the client re-sends ``allow_duplicate=true`` to confirm.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(request.gym_id, user_payload, STAFF)

    try:
        return await management_service.create_member(request)
    except HTTPException:
        # The duplicate gate raises HTTPException(409) directly — re-raise it
        # as-is instead of letting the generic handler mask it as a 500.
        raise
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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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
        "frozen / overdue / incomplete) decides the row shape; the filters and "
        "pagination are applied as given (the view and filters are "
        "independent — no reconciliation), and the rows are "
        "pre-formatted per view. Membership status is derived from "
        "member_memberships (member_memberships_status), not from a "
        "member_status column."
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
    await auth.verify_roles(request.gym_id, user_payload, STAFF)

    try:
        return await crm_members_list_service.get_crm_members_list(request)
    except Exception:
        logger.error(
            "Failed to list members: gym_id=%s, view=%s",
            request.gym_id,
            request.view,
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
        "frozen / overdue / dormant / incomplete) for the CRM members list "
        "subtitle. Counts are membership-derived from "
        "member_memberships_status; incomplete counts members with no "
        "membership who also pay for nobody."
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
    await auth.verify_roles(gym_id, user_payload, STAFF)

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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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


@members_router.post(
    "/{member_id}/points",
    response_model=PointsAdjustResponse,
    summary="Manually adjust a member's points balance",
    description=(
        "Awards or corrects a member's points balance by a signed integer "
        "``amount``. Positive values award points; negative values deduct "
        "(correct) points. The adjustment is rejected when it would take "
        "the balance below zero. Gym staff only."
    ),
    responses={
        200: {"description": "Adjusted — new balance returned"},
        400: {"description": "Member not found, or adjustment would go negative"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member's gym"},
    },
)
@inject
async def adjust_member_points(
    member_id: UUID,
    request: PointsAdjustRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> PointsAdjustResponse:
    """Award or correct a member's points balance. Gym staff only."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=OWNER_ADMIN
    )

    try:
        new_balance = await management_service.adjust_points(member_id, request.amount)
        return PointsAdjustResponse(points_balance=new_balance)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to adjust points: member_id=%s amount=%s",
            member_id,
            request.amount,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to adjust points balance",
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
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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


@members_router.get(
    "/{member_id}/payment-method-status",
    response_model=MemberPaymentMethodStatusResponse,
    summary="Whether the member has any payment method attached",
    description=(
        "Reports whether the member's Stripe customer has ANY payment "
        "method attached, read LIVE from Stripe rather than from the "
        "cached ``stripe_payment_method_id`` column (which only records "
        "the card the CRM last saved as default, so a method attached out "
        "of band would not appear there). A member with no Stripe "
        "customer is ``false`` — nothing can be attached. A Stripe "
        "failure is a 500, NEVER a ``false``: callers gate on this, so "
        "'unknown' must never read as 'nothing on file'. Gym staff only."
    ),
    responses={
        200: {"description": "Status resolved from Stripe"},
        400: {"description": "The member's gym has no Stripe account configured"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
        500: {
            "description": (
                "Stripe / upstream error (no auto-retry) — never reported "
                "as has_payment_method=false"
            )
        },
    },
)
@inject
async def get_member_payment_method_status(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> MemberPaymentMethodStatusResponse:
    """Report whether a member has a payment method attached in Stripe."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        has_payment_method = await management_service.has_payment_method(
            member_id,
        )
        return MemberPaymentMethodStatusResponse(
            has_payment_method=has_payment_method,
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
        # A Stripe failure must surface as an ERROR, never as a false. 500
        # (not 502/503/504) so no proxy auto-retries it.
        logger.error(
            "Stripe error reading payment-method status: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to get payment-method status: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get payment-method status",
        ) from None


@members_router.put(
    "/{member_id}/link",
    summary="Authorize a payer for a member",
    description=(
        "Authorizes a payer (payer_member_id) to pay for this member in ONE "
        "request: the payer signs the gym's payer-auth waiver "
        "(signer_name + consent_acknowledged, version-locked on waiver_version_id "
        "which the client echoes from GET /authorized-payer-waiver), the payer's "
        "and member's names are rendered into the waiver, and the authorization "
        "is recorded against the new signature. A member may have many authorized "
        "payers. This is the authorization layer (who may pay for whom; billing "
        "is per payer via paid_by_member_id) — no subscription is re-billed and "
        "no charges issue."
    ),
    responses={
        200: {"description": "Payer authorized successfully"},
        400: {"description": "Payer invalid / wrong gym / already authorized / no consent"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        409: {"description": "Waiver was updated — reload and re-sign"},
    },
)
@inject
async def link_member_account(
    member_id: UUID,
    request: MembersBillingLinkRequest,
    http_request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Link a member to a paying parent account (staff-only)."""
    user_payload = auth.get_current_user(credentials)
    # get_employee_id_for_member both authorizes (staff of the member's gym) and
    # resolves the operator/witness to stamp on the waiver signature.
    operator_employee_id = await auth.get_employee_id_for_member(
        member_id, user_payload, allowed=STAFF
    )

    try:
        await memberships_service.link_account(
            member_id,
            request.payer_member_id,
            waiver_version_id=request.waiver_version_id,
            signer_name=request.signer_name,
            consent_acknowledged=request.consent_acknowledged,
            # Capture the signer's IP + user-agent for the audit (NOT NULL).
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
            "Failed to link member: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to link member",
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
    request: MembersBillingLinkCheckRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MembersBillingLinkCheckResponse:
    """Check whether a payer can be authorized for a member (staff-only)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await memberships_service.check_link_account(
            member_id,
            request.payer_member_id,
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
    "/{member_id}/link/remove/preview",
    response_model=list[PayerInvoiceChange],
    summary="Preview removing a payer's authorization (pair-scoped cancel)",
    description=(
        "Read-only cost preview: the payer's recurring bill after cancelling "
        "the path member's memberships that payer_member_id funds (current → "
        "new), via the same per-payer cancel preview. Pair-scoped, so a single "
        "entry — empty when there's no billing impact."
    ),
    responses={
        200: {"description": "Preview computed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def preview_remove_authorization(
    member_id: UUID,
    request: MembersBillingRemoveAuthorizationPreviewRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> list[PayerInvoiceChange]:
    """Preview the cascading cancel of removing a payer's authorization."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=OWNER_ADMIN
    )

    try:
        return await memberships_service.preview_remove_authorization(
            member_id,
            request.payer_member_id,
        )
    except Exception:
        logger.error(
            "Failed to preview remove authorization: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview removing the authorization",
        ) from None


@members_router.post(
    "/{member_id}/link/remove",
    response_model=MemberMembershipsCancelResponse,
    summary="Remove a payer's authorization (pair-scoped cascading cancel)",
    description=(
        "Cancels the path member's live recurring memberships that "
        "payer_member_id funds (the existing per-membership cancel converges "
        "Stripe), then de-authorizes the pair. The signature audit row persists. "
        "Memberships paid by other payers, and this payer's memberships for other "
        "members, are untouched. Returns the cascading cancel's outcome — the "
        "same item_id → cancel_date map a direct cancel returns (empty when the "
        "relationship funded nothing) — so the caller can show what was "
        "cancelled. Call .../remove/preview first to confirm impact."
    ),
    responses={
        200: {"description": "Authorization removed and memberships cancelled"},
        400: {"description": "That payer is not authorized for this member"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member not found"},
        207: {
            "description": (
                "Partial cascade — some memberships cancelled, some failed "
                "(body has succeeded_item_ids/failed_item_ids); the "
                "authorization row is left intact. A 2xx, never auto-retried."
            )
        },
        500: {"description": "Total failure — nothing cancelled (Stripe/sync)"},
    },
)
@inject
async def remove_authorization(
    member_id: UUID,
    request: MembersBillingRemoveAuthorizationRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MemberMembershipsCancelResponse:
    """Remove a payer's authorization, cancelling the pair's memberships."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=OWNER_ADMIN
    )

    try:
        cancel_dates = await memberships_service.remove_authorization(
            member_id,
            request.payer_member_id,
            request.idempotency_key,
        )
        return MemberMembershipsCancelResponse(
            cancel_dates={
                str(item_id): cancel_date
                for item_id, cancel_date in cancel_dates.items()
            },
        )
    except PartialCancelError as exc:
        # The cascading cancel partially applied (one payer converged, a later
        # one failed). Mirror the cancel router: this is a real, parseable
        # RESULT, so RETURN it as 207 Multi-Status with the succeeded/failed
        # split (a 2xx — a proxy never auto-retries a partial). The
        # authorization row is left intact (the de-authorize runs only after a
        # full cancel).
        succeeded_item_ids = sorted(str(i) for i in exc.succeeded)
        failed_item_ids = sorted(str(i) for i in exc.failed_item_ids)
        logger.error(
            "Remove-authorization cancel partially applied: member_id=%s "
            "succeeded=%s failed_payer=%s failed_item_ids=%s",
            member_id,
            succeeded_item_ids,
            exc.failed_payer_id,
            failed_item_ids,
            exc_info=True,
        )
        return JSONResponse(
            status_code=status.HTTP_207_MULTI_STATUS,
            content={
                "message": str(exc),
                "succeeded_item_ids": succeeded_item_ids,
                "failed_item_ids": failed_item_ids,
            },
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
        # Total failure — nothing cancelled, so nothing de-authorized. 500, not
        # 502, so the gateway never auto-retries it.
        logger.error(
            "Remove-authorization failed (Stripe, nothing cancelled): "
            "member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to remove authorization: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to remove the authorization",
        ) from None


@members_router.get(
    "/{member_id}/authorized-payer-waiver",
    response_model=AuthorizedPayerWaiverResponse,
    summary="Get the payer-auth waiver a payer must sign",
    description=(
        "Returns the member's gym payer-auth waiver — its id, "
        "current version id, name, and body — for the front-desk sign dialog to "
        "display before authorizing a payer. The link flow records the signature "
        "against this same current version, so the caller only echoes back the "
        "signer's name + consent."
    ),
    responses={
        200: {"description": "Default waiver returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member or payer-auth waiver not found"},
    },
)
@inject
async def get_authorized_payer_waiver(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    waivers_service: WaiversService = Depends(
        Provide[DependencyInjector.waivers_service]
    ),
) -> AuthorizedPayerWaiverResponse:
    """Resolve the payer-auth waiver (with body) for a member."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await waivers_service.get_payer_auth_waiver_with_body_for_member(
            member_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to get authorized-payer waiver: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get authorized-payer waiver",
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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

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


@members_router.get(
    "/{member_id}/upcoming-invoice",
    response_model=PreviewInvoice | None,
    summary="Get member's upcoming invoice",
    description=(
        "Returns the upcoming (next) Stripe invoice preview for the "
        "member's paying account, or null when there is no recurring "
        "subscription."
    ),
    responses={
        200: {"description": "Upcoming invoice retrieved (or null)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_member_upcoming_invoice(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    management_service: MembersManagementService = Depends(
        Provide[DependencyInjector.members_management_service]
    ),
) -> PreviewInvoice | None:
    """Fetch the upcoming invoice preview for a member's account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await management_service.get_upcoming_invoice(member_id)
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
            "Failed to get upcoming invoice: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get upcoming invoice",
        ) from None


@members_router.get(
    "/{member_id}/payments",
    response_model=list[BillingPaymentRecord],
    summary="List member payment history (paginated)",
    description=(
        "Returns a page of the member's payment history — the charges that "
        "paid for any membership this member has held (by membership "
        "item_id) plus their own direct charges, newest first — each "
        "labelled with who was charged."
    ),
    responses={
        200: {"description": "Payment history page retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member not found"},
    },
)
@inject
async def list_member_payments(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    payments_service: MembersPaymentsService = Depends(
        Provide[DependencyInjector.members_payments_service]
    ),
    limit: int = 20,
    offset: int = 0,
) -> list[BillingPaymentRecord]:
    """List one page of a member's payment history."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await payments_service.list_payments(
            member_id,
            limit=limit,
            offset=offset,
        )
    except Exception:
        logger.error(
            "Failed to list payments: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list payments",
        ) from None
