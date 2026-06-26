"""API routes for the member memberships domain."""

import logging
from typing import Annotated

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.memberships.memberships_exceptions import PartialCancelError
from src.memberships.memberships_schema import (
    MemberMembershipsAddDiscountsRequest,
    MemberMembershipsBatchRepriceRequest,
    MemberMembershipsBatchRepriceResponse,
    MemberMembershipsCancelPreviewRequest,
    MemberMembershipsCancelRequest,
    MemberMembershipsCancelResponse,
    MemberMembershipsChargeCardRequest,
    MemberMembershipsEndRequest,
    MemberMembershipsEndResponse,
    MemberMembershipsFreezeRequest,
    MemberMembershipsMarkPaidCashRequest,
    MemberMembershipsRefundRequest,
    MemberMembershipsRefundResponse,
    MemberMembershipsRemoveDiscountsRequest,
    MemberMembershipsStartPreviewResponse,
    MemberMembershipsStartRequest,
    MemberMembershipsStartResponse,
    MemberMembershipsStartStatus,
    MemberMembershipsUnfreezeRequest,
    MemberMembershipsUpdatePriceRequest,
    MemberMembershipsUpdatePriceResponse,
    MemberMembershipsUpgradePreviewRequest,
    MemberMembershipsUpgradeRequest,
    MemberMembershipsUpgradeResponse,
    PayerInvoiceChange,
)
from src.memberships.service.memberships_refund import (
    MemberMembershipsRefund,
)
from src.memberships.service.memberships_service import (
    MemberMembershipsService,
)
from src.payments.payments_exceptions import PaymentsStripeError
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.auth import Auth, security
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_membership_reprice_handler import (
    MembershipRepriceTaskHandler,
)
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_exceptions import MembershipInTaskError

logger = logging.getLogger(__name__)

member_memberships_router = APIRouter(
    prefix="/api/v1/member_memberships",
    tags=["member_memberships"],
)


@member_memberships_router.delete(
    "/",
    response_model=MemberMembershipsCancelResponse,
    summary="Cancel one or more memberships",
    description=(
        "Cancels one or more active memberships for a member (a single "
        "cancel is a one-element ``item_ids`` list). Sets each cancel_date "
        "to the membership's next_due_date, or today if missing or in the "
        "past. Memberships funded by different payers are each converged "
        "once. Returns a map of item_id → resolved cancel_date (the date "
        "through which each membership remains active)."
    ),
    responses={
        200: {"description": "Membership(s) cancelled successfully"},
        207: {
            "description": (
                "Partial cancel — some memberships cancelled, some failed. "
                "Body carries succeeded_item_ids + failed_item_ids; the caller "
                "re-issues the cancel for the failed items. A 2xx (not an "
                "error) so a proxy never auto-retries a partial result."
            )
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        500: {"description": "Total failure — nothing cancelled (Stripe/sync)"},
    },
)
@inject
async def cancel_membership(
    request: MemberMembershipsCancelRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> MemberMembershipsCancelResponse:
    """Cancel one or more memberships for a member.

    Syncs each affected payer's cancellation to Stripe, then updates the
    CRM database.

    Args:
        request: The item_ids to cancel, the member, and the idempotency key.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
        tasks_service: Injected tasks service (the in-task guard).

    Raises:
        HTTPException: 401 if not authenticated,
            403 if not authorized,
            409 if a membership is inside an unfinished task,
            500 on a total Stripe failure or unexpected error
            (a PARTIAL cancel is RETURNED as 207, not raised).
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task(
            request.item_ids,
        )
        cancel_dates = await memberships_service.cancel_many(
            request.item_ids,
            request.member_id,
            request.idempotency_key,
        )
        return MemberMembershipsCancelResponse(
            cancel_dates={
                str(item_id): cancel_date
                for item_id, cancel_date in cancel_dates.items()
            },
        )
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except PartialCancelError as exc:
        # A later payer's converge failed AFTER an earlier payer succeeded —
        # the batch is partial. This is a real, parseable RESULT (not an error):
        # RETURN it as 207 Multi-Status with the succeeded/failed split so the
        # caller shows the accurate outcome and re-issues the cancel for the
        # failed items. 207 is a 2xx, so a proxy never auto-retries a partial
        # (which would needlessly re-cancel the already-succeeded payers).
        succeeded_item_ids = sorted(str(i) for i in exc.succeeded)
        failed_item_ids = sorted(str(i) for i in exc.failed_item_ids)
        logger.error(
            "Cancel partially applied: member_id=%s succeeded=%s "
            "failed_payer=%s failed_item_ids=%s",
            request.member_id,
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
        # Total failure — nothing was cancelled (no payer succeeded). 500, not
        # 502: a 502 is in the proxy auto-retry family and we don't want a
        # partial-or-total cancel auto-retried at the gateway.
        logger.error(
            "Cancel failed (Stripe, nothing cancelled): item_ids=%s, "
            "member_id=%s",
            request.item_ids,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to cancel memberships: item_ids=%s, member_id=%s",
            request.item_ids,
            request.member_id,
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
    response_model=MemberMembershipsStartResponse,
    summary="Start memberships for a payer's family",
    description=(
        "Creates every membership in the request for the paying account's "
        "family in one call (a single membership = a one-item list), with "
        "per-membership discounts applied before the first charge. Bills at "
        "most two charges: one consolidated one-time invoice plus one "
        "recurring converge. Returns the per-membership breakdown — a "
        "failed charge group surfaces there, not as an error status."
    ),
    responses={
        201: {"description": "All memberships created (full breakdown)"},
        207: {
            "description": (
                "Partial — some memberships created, some failed; the "
                "results[] breakdown carries the per-item split. A 2xx, never "
                "auto-retried."
            )
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update these members"},
        500: {"description": "Total failure — nothing created (Stripe/sync)"},
    },
)
@inject
async def start_membership(
    request: MemberMembershipsStartRequest,
    response: Response,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MemberMembershipsStartResponse:
    """Start the request's memberships for the payer's family.

    Args:
        request: Payer + the memberships to create (price + discounts each).
        response: Injected so a mixed breakdown can be flagged 207 (below).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.payer_member_id, user_payload)
    for item_member_id in {item.member_id for item in request.memberships}:
        await auth.verify_can_view_member(item_member_id, user_payload)

    try:
        result = await memberships_service.start(request)
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
        # Total failure before any membership was created. 500, not 502: a 502
        # is in the proxy auto-retry family, and auto-retrying a create risks
        # duplicate memberships/charges.
        logger.error(
            "Failed to start memberships (Stripe): payer_member_id=%s, "
            "gym_id=%s",
            request.payer_member_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to start memberships: payer_member_id=%s, gym_id=%s",
            request.payer_member_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to start memberships",
        ) from None

    # A breakdown with any failed charge group is a partial -> 207 Multi-Status
    # (the results[] carries the per-item split). 207 is a 2xx, so a proxy never
    # auto-retries a partial create; an all-created breakdown stays 201.
    if any(
        item.status == MemberMembershipsStartStatus.failed
        for item in result.results
    ):
        response.status_code = status.HTTP_207_MULTI_STATUS
    return result


@member_memberships_router.put(
    "/price",
    response_model=MemberMembershipsUpdatePriceResponse,
    summary="Reprice ONE membership to the plan's current price",
    description=(
        "Moves a membership onto its plan's currently active price — a "
        "DIRECT, synchronous reprice (cancel-old-row + insert-successor + "
        "Stripe converge), like cancel. Returns the successor membership id "
        "(the same id when it was already on the price — a no-op). Tasks are "
        "only for the per-plan BATCH endpoint. A membership inside an "
        "unfinished batch task is rejected (409)."
    ),
    responses={
        200: {"description": "Repriced; the successor membership id"},
        400: {"description": "Invalid request (cancelled / ended membership)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": "Membership is inside an unfinished task"},
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> MemberMembershipsUpdatePriceResponse:
    """Reprice one membership to its plan's active price (direct; 200 + id).

    Args:
        request: Update price request with proration_behavior.
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
        tasks_service: Injected tasks service (the in-task guard — a
            membership mid-batch-task is rejected 409).
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        new_item_id = await memberships_service.update_price(
            item_id=request.item_id,
            member_id=request.member_id,
            proration_behavior=request.proration_behavior,
        )
        return MemberMembershipsUpdatePriceResponse(item_id=new_item_id)
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
    "/upgrade",
    response_model=MemberMembershipsUpgradeResponse,
    summary="Upgrade ONE membership to a different plan (charge difference)",
    description=(
        "Moves a membership to a DIFFERENT plan's currently active price (a "
        "cross-plan upgrade) and charges the prorated DIFFERENCE now when "
        "``proration_behavior`` is ``prorate_to_anchor`` and the new price is "
        "higher; a downgrade/equal charges nothing. A DIRECT, synchronous op "
        "(cancel-old-row + insert-successor-on-the-new-plan + Stripe converge), "
        "like reprice. Returns the successor membership id. The target must be "
        "a DIFFERENT recurring plan on the same billing interval (same-plan "
        "moves use PUT /price). A membership inside an unfinished batch task is "
        "rejected (409)."
    ),
    responses={
        200: {"description": "Upgraded; the successor membership id"},
        400: {"description": "Invalid request (same plan / window / state)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": "Membership is inside an unfinished task"},
        500: {"description": "Stripe error"},
    },
)
@inject
async def upgrade_membership(
    request: MemberMembershipsUpgradeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> MemberMembershipsUpgradeResponse:
    """Upgrade one membership to a different plan (direct; 200 + successor id).

    Args:
        request: Upgrade request (target_plan_id + proration_behavior).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
        tasks_service: Injected tasks service (the in-task guard — a
            membership mid-batch-task is rejected 409).
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        new_item_id = await memberships_service.upgrade(
            item_id=request.item_id,
            member_id=request.member_id,
            target_plan_id=request.target_plan_id,
            proration_behavior=request.proration_behavior,
            idempotency_key=request.idempotency_key,
        )
        return MemberMembershipsUpgradeResponse(item_id=new_item_id)
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to upgrade membership: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to upgrade membership",
        ) from None


@member_memberships_router.post(
    "/upgrade/preview",
    response_model=DueNowVsRecurringPreview | None,
    summary="Preview upgrading a membership to a different plan",
    description=(
        "Dry-run of the upgrade endpoint: runs every validation and returns "
        "the due-now prorated difference (``due_now``, null on a "
        "downgrade/equal) plus the new steady-state monthly bill "
        "(``recurring``). Writes and bills nothing."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        400: {"description": "Invalid request (same plan / window / state)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_upgrade_membership(
    request: MemberMembershipsUpgradePreviewRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> DueNowVsRecurringPreview | None:
    """Preview what upgrading a membership to a different plan would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await memberships_service.upgrade_preview(
            item_id=request.item_id,
            member_id=request.member_id,
            target_plan_id=request.target_plan_id,
            proration_behavior=request.proration_behavior,
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to preview membership upgrade: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership upgrade",
        ) from None


@member_memberships_router.post(
    "/end",
    response_model=MemberMembershipsEndResponse,
    summary="End a one-time / trial membership early",
    description=(
        "Ends a ONE-TIME / TRIAL membership now by setting its end_date to "
        "today (→ status 'ended'). A one-time pack is a terminal invoice with "
        "no subscription line, so this is a pure DB write — NO Stripe action "
        "and no money movement (a refund is the separate POST /refund flow). "
        "Recurring memberships are rejected (use DELETE / to cancel)."
    ),
    responses={
        200: {"description": "Ended; the resolved end_date"},
        400: {"description": "Recurring / already ended / already cancelled"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Membership not found"},
    },
)
@inject
async def end_membership(
    request: MemberMembershipsEndRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MemberMembershipsEndResponse:
    """End a one-time / trial membership early (200 + the resolved end_date).

    Args:
        request: The membership to end (item_id + member_id).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        memberships_service: Injected memberships service.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        end_date = await memberships_service.end_one_time(
            request.item_id,
            request.member_id,
        )
        return MemberMembershipsEndResponse(end_date=end_date)
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
            "Failed to end membership: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to end membership",
        ) from None


@member_memberships_router.post(
    "/reprice-plan",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=MemberMembershipsBatchRepriceResponse,
    summary="Batch-upgrade a plan's members to its active price",
    description=(
        "Upgrades EVERY member on the plan to the plan's currently active "
        "price. The backend auto-discovers every live membership not already "
        "on the active price (skipping any already mid-task), creates one "
        "tracked task with an item per membership, runs it in the "
        "background, and returns the task_id — poll GET /api/v1/tasks/"
        "{task_id} for per-membership progress. Returns task_id=null when "
        "nothing needs upgrading."
    ),
    responses={
        202: {"description": "Batch accepted; poll the returned task"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def batch_reprice_plan(
    request: MemberMembershipsBatchRepriceRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    reprice_task_handler: MembershipRepriceTaskHandler = Depends(
        Provide[DependencyInjector.membership_reprice_task_handler]
    ),
    tasks_executor: TasksExecutor = Depends(
        Provide[DependencyInjector.tasks_executor]
    ),
) -> MemberMembershipsBatchRepriceResponse:
    """Batch-reprice a plan's members to its active price (202 + task_id).

    Args:
        request: Batch reprice request (plan_id, gym_id, proration_behavior).
        credentials: Bearer token credentials.
        auth: Injected auth service.
        reprice_task_handler: Injected membership_reprice task handler.
        tasks_executor: Injected tasks executor (fires the run).
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        task_id, count = await reprice_task_handler.create_batch(
            gym_id=request.gym_id,
            plan_id=request.plan_id,
            proration_behavior=request.proration_behavior,
        )
        if task_id is not None:
            tasks_executor.start_in_background(task_id)
        return MemberMembershipsBatchRepriceResponse(
            task_id=task_id,
            membership_count=count,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to batch-reprice plan %s (gym %s)",
            request.plan_id,
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to batch-reprice plan",
        ) from None


@member_memberships_router.post(
    "/preview",
    response_model=MemberMembershipsStartPreviewResponse,
    summary="Preview starting memberships",
    description=(
        "Dry-run of the start endpoint: runs every validation, stages the "
        "request (discounts included) as preview-only rows, and returns "
        "the three-way invoice split (one_time / due_now / recurring) "
        "without charging anything or leaving any rows behind."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update these members"},
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
) -> MemberMembershipsStartPreviewResponse:
    """Preview what starting the request's memberships would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.payer_member_id, user_payload)
    for item_member_id in {item.member_id for item in request.memberships}:
        await auth.verify_can_view_member(item_member_id, user_payload)

    try:
        return await memberships_service.preview_start(request)
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to preview start memberships: payer_member_id=%s",
            request.payer_member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership start",
        ) from None


@member_memberships_router.post(
    "/cancel/preview",
    response_model=list[PayerInvoiceChange],
    summary="Preview cancelling one or more memberships",
    description=(
        "Dry-run of the cancel endpoint: a per-payer list of the post-cancel "
        "subscription state (current → new). One entry per payer that funds "
        "any of the item_ids — a single cancel is one payer (one entry); a "
        "member's memberships split across payers yield several entries. A "
        "payer with no billing change is reported with affected=false."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def preview_cancel_membership(
    request: MemberMembershipsCancelPreviewRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> list[PayerInvoiceChange]:
    """Preview what cancelling one or more memberships would charge."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await memberships_service.preview_cancel_many(
            request.item_ids,
            request.member_id,
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to preview cancel memberships: item_ids=%s, member_id=%s",
            request.item_ids,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to preview membership cancel",
        ) from None


@member_memberships_router.post(
    "/discounts/add",
    response_model=DueNowVsRecurringPreview | None,
    summary="Add applied-discount rows to a membership (or preview)",
    description=(
        "Adds an applied-discount row per discount id, then re-syncs the Stripe "
        "subscription — no mid-cycle invoice is cut. A preset already applied is "
        "left frozen. With ``preview=true`` "
        "nothing is committed: the adds are staged as preview rows, the "
        "resulting invoice preview is returned, and the staged rows are removed."
    ),
    responses={
        200: {"description": "Discounts added, or preview returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def add_membership_discounts(
    request: MemberMembershipsAddDiscountsRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> DueNowVsRecurringPreview | None:
    """Add applied-discount rows to a membership, or preview the addition."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        return await memberships_service.add_discounts(
            item_id=request.item_id,
            member_id=request.member_id,
            discount_ids=request.discount_ids,
            idempotency_key=request.idempotency_key,
            preview=request.preview,
        )
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to add membership discounts: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to add membership discounts",
        ) from None


@member_memberships_router.post(
    "/discounts/remove",
    response_model=DueNowVsRecurringPreview | None,
    summary="Remove applied-discount rows from a membership (or preview)",
    description=(
        "Removes the named applied-discount rows, then re-syncs the Stripe "
        "subscription — no mid-cycle invoice is cut. With ``preview=true`` "
        "nothing is committed: the rows are staged as preview-removed, the "
        "resulting invoice preview is returned, and the rows are restored."
    ),
    responses={
        200: {"description": "Discounts removed, or preview returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
    },
)
@inject
async def remove_membership_discounts(
    request: MemberMembershipsRemoveDiscountsRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> DueNowVsRecurringPreview | None:
    """Remove applied-discount rows from a membership, or preview the removal."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        return await memberships_service.remove_discounts(
            item_id=request.item_id,
            member_id=request.member_id,
            applied_ids=request.applied_ids,
            idempotency_key=request.idempotency_key,
            preview=request.preview,
        )
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to remove membership discounts: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to remove membership discounts",
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
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> None:
    """Mark a recurring membership's open invoice as paid via cash."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        await memberships_service.mark_paid_cash(
            item_id=request.item_id,
            member_id=request.member_id,
            idempotency_key=request.idempotency_key,
        )
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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
        "An optional ``payment_method_id`` bills a one-off card "
        "(attached, billed once, detached) instead of the payer's "
        "saved default. The existing ``invoice.paid`` webhook writes "
        "the CRM invoice and charge rows."
    ),
    responses={
        204: {"description": "Card charged successfully"},
        400: {"description": "Invalid request or gym mismatch"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member profile not found"},
        500: {"description": "Stripe / upstream error (no auto-retry)"},
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
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
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


@member_memberships_router.post(
    "/refund",
    response_model=MemberMembershipsRefundResponse,
    summary="Refund a prior charge (card via Stripe, or cash)",
    description=(
        "Refunds a prior succeeded charge on a member's payment "
        "history (full or partial). A card charge is reversed "
        "through Stripe and recorded immediately; a cash charge is "
        "recorded as a cash refund with no Stripe call."
    ),
    responses={
        200: {"description": "Refund processed"},
        400: {"description": "Charge is not refundable or amount invalid"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to view this member"},
        404: {"description": "Member or charge not found"},
        500: {"description": "Stripe / upstream error (no auto-retry)"},
    },
)
@inject
async def refund_charge(
    request: MemberMembershipsRefundRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    refund_service: MemberMembershipsRefund = Depends(
        Provide[DependencyInjector.member_memberships_refund_service]
    ),
) -> MemberMembershipsRefundResponse:
    """Refund a prior charge for a member (card via Stripe, or cash)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await refund_service.refund_charge(request)
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
            "Stripe error refunding charge: member_id=%s, charge_id=%s",
            request.member_id,
            request.charge_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to refund charge: member_id=%s, charge_id=%s",
            request.member_id,
            request.charge_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to refund charge",
        ) from None
