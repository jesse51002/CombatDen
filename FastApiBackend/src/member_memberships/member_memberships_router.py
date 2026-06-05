"""API routes for the member memberships domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.member_memberships.schema.member_memberships_schema import (
    MemberMembershipsApplyDiscountsRequest,
    MemberMembershipsCancelResponse,
    MemberMembershipsChargeCardRequest,
    MemberMembershipsFreezeRequest,
    MemberMembershipsMarkPaidCashRequest,
    MemberMembershipsStartRequest,
    MemberMembershipsUnfreezeRequest,
    MemberMembershipsUpdatePriceRequest,
)
from src.member_memberships.service.memberships.member_memberships_service import (
    MemberMembershipsService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

member_memberships_router = APIRouter(
    prefix="/api/v1/member_memberships",
    tags=["member_memberships"],
)


@member_memberships_router.delete(
    "/",
    response_model=MemberMembershipsCancelResponse,
    summary="Cancel a membership",
    description=(
        "Cancels a specific active membership for a member. "
        "Sets cancel_date to the membership's next_due_date, "
        "or today if next_due_date is missing or in the past. "
        "Returns the resolved cancel_date (the date through "
        "which the membership remains active)."
    ),
    responses={
        200: {"description": "Membership cancelled successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def cancel_membership(
    item_id: UUID,
    member_id: UUID,
    idempotency_key: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MemberMembershipsCancelResponse:
    """Cancel a specific membership for a member.

    Syncs the cancellation to Stripe first, then updates the
    CRM database.

    Args:
        member_id: The member.
        item_id: The membership item to cancel.
        idempotency_key: Caller-supplied key scoped to this cancel.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized,
            502 on Stripe errors,
            500 on unexpected errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        cancel_date = await memberships_service.cancel(item_id, member_id, idempotency_key)
        return MemberMembershipsCancelResponse(cancel_date=cancel_date)
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
            "Failed to cancel membership: item_id=%s, member_id=%s",
            item_id,
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel membership",
        ) from None


@member_memberships_router.post(
    "/freeze",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Freeze a member's account",
    description=(
        "Freezes billing for a member's account (account-level). "
        "Accepts any family member's member_id and resolves "
        "to the paying parent. Idempotent — re-freezing updates "
        "the freeze end date."
    ),
    responses={
        204: {"description": "Account frozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def freeze_membership(
    request: MemberMembershipsFreezeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Freeze a member's account.

    Args:
        request: Freeze request with member_id, gym_id, freeze_months.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.freeze(
            request.member_id,
            request.gym_id,
            request.freeze_months,
            request.idempotency_key,
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
            "Failed to freeze account: member_id=%s, gym_id=%s",
            request.member_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to freeze account",
        ) from None


@member_memberships_router.post(
    "/unfreeze",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unfreeze a member's account",
    description=(
        "Resumes billing for a member's account (account-level). "
        "If not frozen, performs a no-op sync for consistency."
    ),
    responses={
        204: {"description": "Account unfrozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def unfreeze_membership(
    request: MemberMembershipsUnfreezeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Unfreeze a member's account.

    Args:
        request: Unfreeze request with member_id, gym_id.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.unfreeze(
            request.member_id,
            request.gym_id,
            request.idempotency_key,
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
            "Failed to unfreeze account: member_id=%s, gym_id=%s",
            request.member_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unfreeze account",
        ) from None


@member_memberships_router.post(
    "/",
    status_code=status.HTTP_201_CREATED,
    summary="Start a new membership",
    description=(
        "Creates a new membership for a member. Validates "
        "the plan/price, checks for duplicates and frozen "
        "accounts, syncs to Stripe, then inserts the CRM row."
    ),
    responses={
        201: {"description": "Membership created successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def start_membership(
    request: MemberMembershipsStartRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Start a new membership for a member.

    Args:
        request: Start request with plan, price, and start date.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.start(
            member_id=request.member_id,
            gym_id=request.gym_id,
            plan_id=request.plan_id,
            price_id=request.price_id,
            idempotency_key=request.idempotency_key,
            prorate=request.prorate,
            paid_with_cash=request.paid_with_cash,
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
            "Failed to start membership: member_id=%s, gym_id=%s, plan_id=%s",
            request.member_id,
            request.gym_id,
            request.plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to start membership",
        ) from None


@member_memberships_router.put(
    "/price",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Upgrade membership to the plan's current price",
    description=(
        "Moves a membership onto its plan's currently active "
        "price. Swaps the old price for the active one in "
        "Stripe, then updates the CRM row. If the membership "
        "is already on the active price, no CRM update occurs "
        "but Stripe is still re-synced defensively."
    ),
    responses={
        204: {"description": "Price updated successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def update_membership_price(
    request: MemberMembershipsUpdatePriceRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Upgrade a membership to its plan's currently active price.

    Args:
        request: Update price request with prorate flag.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.update_price(
            item_id=request.item_id,
            member_id=request.member_id,
            idempotency_key=request.idempotency_key,
            prorate=request.prorate,
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
            "Failed to update membership price: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update membership price",
        ) from None


@member_memberships_router.post(
    "/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview starting a membership",
    description=(
        "Dry-run of the start endpoint: runs every validation "
        "and returns the Stripe invoice preview without "
        "creating any CRM rows or Stripe resources."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_start_membership(
    request: MemberMembershipsStartRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview what starting a membership would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await memberships_service.preview_start(
            member_id=request.member_id,
            gym_id=request.gym_id,
            plan_id=request.plan_id,
            price_id=request.price_id,
            prorate=request.prorate,
            paid_with_cash=request.paid_with_cash,
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
            "Failed to preview start membership: member_id=%s, plan_id=%s",
            request.member_id,
            request.plan_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership start",
        ) from None


@member_memberships_router.post(
    "/cancel/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview cancelling a membership",
    description=(
        "Dry-run of the cancel endpoint: runs every validation "
        "and returns the Stripe invoice preview for the "
        "post-cancel subscription state. Returns null for the "
        "last active membership (pure cancellation has no "
        "upcoming invoice)."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_cancel_membership(
    item_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview what cancelling a membership would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await memberships_service.preview_cancel(item_id, member_id)
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
            "Failed to preview cancel membership: item_id=%s, member_id=%s",
            item_id,
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership cancel",
        ) from None


@member_memberships_router.post(
    "/price/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview updating a membership's price",
    description=(
        "Dry-run of the update-price endpoint: runs every "
        "validation and returns the Stripe invoice preview for "
        "the post-swap subscription state."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_update_membership_price(
    request: MemberMembershipsUpdatePriceRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview what updating a membership's price would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await memberships_service.preview_update_price(
            item_id=request.item_id,
            member_id=request.member_id,
            prorate=request.prorate,
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
            "Failed to preview update membership price: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership price update",
        ) from None


@member_memberships_router.put(
    "/discounts",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Add / remove a membership's discount snapshots",
    description=(
        "Applies discounts as immutable snapshots on an existing "
        "membership: adds a frozen snapshot per regular preset and "
        "per entered linked discount, and removes named snapshots. "
        "A preset already applied is left frozen. A linked discount "
        "requires a same-plan family sibling. Re-syncs the Stripe "
        "subscription — no mid-cycle invoice is cut."
    ),
    responses={
        204: {"description": "Discounts applied successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def apply_membership_discounts(
    request: MemberMembershipsApplyDiscountsRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Add / remove discount snapshots on an existing membership.

    Args:
        request: Apply request with preset / linked adds and snapshot
            removes.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.apply_discounts(
            item_id=request.item_id,
            member_id=request.member_id,
            add_preset_ids=request.add_preset_ids,
            remove_applied_ids=request.remove_applied_ids,
            idempotency_key=request.idempotency_key,
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
            "Failed to apply membership discounts: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to apply membership discounts",
        ) from None


@member_memberships_router.post(
    "/discounts/preview",
    response_model=PaymentsInvoicePreviewResponse | None,
    summary="Preview a membership's discounted subscription",
    description=(
        "Runs the membership validation and returns the Stripe "
        "invoice preview for the membership's current applied "
        "discount snapshots, without mutating the subscription."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_membership_discounts(
    item_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> PaymentsInvoicePreviewResponse | None:
    """Preview the membership's current discounted subscription."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await memberships_service.preview_apply_discounts(
            item_id=item_id,
            member_id=member_id,
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
            "Failed to preview membership discounts: item_id=%s, member_id=%s",
            item_id,
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership discounts",
        ) from None


@member_memberships_router.post(
    "/mark-paid-cash",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Mark a recurring membership's open invoice as paid via cash",
    description=(
        "Finds the currently-open Stripe invoice for the "
        "subscription this membership belongs to and marks it as "
        "paid out of band. No card is charged. Only applies to "
        "recurring memberships. The existing invoice.paid webhook "
        "writes the CRM invoice and charge rows."
    ),
    responses={
        204: {"description": "Invoice marked paid successfully"},
        400: {"description": "Not recurring, no open invoice, or invalid state"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Membership not found"},
    },
)
@inject
async def mark_membership_paid_cash(
    request: MemberMembershipsMarkPaidCashRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Mark a recurring membership's open invoice as paid via cash."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.mark_paid_cash(
            item_id=request.item_id,
            member_id=request.member_id,
            idempotency_key=request.idempotency_key,
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
            "Failed to mark membership paid via cash: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to mark membership paid via cash",
        ) from None


@member_memberships_router.post(
    "/charge-card",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Charge a member's card for an ad-hoc amount",
    description=(
        "Creates a one-off Stripe invoice for ``amount_cents`` "
        "with ``reason`` as the description and line-item name, "
        "then pays it. If ``paid_cash`` is true the invoice is "
        "marked paid out of band instead of charging the card. "
        "The existing ``invoice.paid`` webhook writes the CRM "
        "invoice and charge rows."
    ),
    responses={
        204: {"description": "Card charged successfully"},
        400: {"description": "Invalid request or gym mismatch"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member profile not found"},
        502: {"description": "Stripe error"},
    },
)
@inject
async def charge_member_card(
    request: MemberMembershipsChargeCardRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> None:
    """Charge a member's card (or mark as cash) for an ad-hoc amount."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await memberships_service.charge_card(request)
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
            "Failed to charge member card: member_id=%s, gym_id=%s, amount_cents=%s",
            request.member_id,
            request.gym_id,
            request.amount_cents,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to charge member card",
        ) from None
