"""API routes for the member memberships domain."""

import logging
from typing import Annotated

import stripe
from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Response, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.memberships.memberships_exceptions import (
    MembershipStartReplayError,
    PartialCancelError,
    WaiverGateError,
)
from src.memberships.memberships_schema import (
    MemberMembershipsAddDiscountsRequest,
    MemberMembershipsBatchRepriceRequest,
    MemberMembershipsBatchRepriceResponse,
    MemberMembershipsCancelOneTimeRequest,
    MemberMembershipsCancelOneTimeResponse,
    MemberMembershipsCancelPreviewRequest,
    MemberMembershipsCancelRequest,
    MemberMembershipsCancelResponse,
    MemberMembershipsChargeCardRequest,
    MemberMembershipsChargeCardResponse,
    MemberMembershipsFreezeRequest,
    MemberMembershipsMarkPaidCashRequest,
    MemberMembershipsRefundRequest,
    MemberMembershipsRefundResponse,
    MemberMembershipsRemoveDiscountsRequest,
    MemberMembershipsRetryCardRequest,
    MemberMembershipsRetryCardResponse,
    MemberMembershipsRetryCardStatus,
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
from src.payments.payments_exceptions import (
    PaymentsNotCollectedError,
    PaymentsStripeError,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.auth import STAFF, Auth, security
from src.shared.paying_member_lock import LockBusyError
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_membership_reprice_handler import (
    MembershipRepriceTaskHandler,
)
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_exceptions import MembershipInTaskError

logger = logging.getLogger(__name__)

# Every handler below whose service takes the payer's billing lock can answer a
# BUSY payer, so each documents this 409 and each RE-RAISES ``LockBusyError``
# (see the `except LockBusyError: raise` arms) instead of letting its generic
# `except Exception` bury it in a 500. One string so the route docs cannot drift.
BUSY_PAYER_409 = (
    "the payer is busy (another billing op holds their lock) — retryable"
)

member_memberships_router = APIRouter(
    prefix="/api/v1/member_memberships",
    tags=["member_memberships"],
)


@member_memberships_router.delete(
    "/",
    response_model=MemberMembershipsCancelResponse,
    summary="Cancel one or more memberships",
    description=(
        "Cancels one or more active memberships. Returns item_id → cancel_date "
        "map. Partial success returns 207 with succeeded/failed split."
    ),
    responses={
        200: {"description": "Membership(s) cancelled successfully"},
        207: {
            "description": (
                "Partial cancel — body carries succeeded_item_ids + failed_item_ids."
            )
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {
            "description": (
                f"A membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    """Cancel one or more memberships; partial success returns 207."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

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
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
    except MembershipInTaskError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except PartialCancelError as exc:
        # Partial result — earlier payer(s) succeeded, this one failed; return 207.
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
    description="Freezes billing for a member's account. Idempotent.",
    responses={
        204: {"description": "Account frozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
    """Freeze a member's account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await memberships_service.freeze(
            request.member_id,
            request.freeze_months,
            request.idempotency_key,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
            "Failed to freeze account: member_id=%s",
            request.member_id,
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
    description="Resumes billing for a member's account. No-op if not frozen.",
    responses={
        204: {"description": "Account unfrozen successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
    """Unfreeze a member's account."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await memberships_service.unfreeze(
            request.member_id,
            request.idempotency_key,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
            "Failed to unfreeze account: member_id=%s",
            request.member_id,
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
        "Creates memberships for a payer's family. Bills at most two charges: "
        "one consolidated one-time invoice + one recurring converge."
    ),
    responses={
        201: {"description": "All memberships created (full breakdown)"},
        # Same model on the 207 as on the 201 so a client generator sees the
        # per-item breakdown BODY, not just a description. This is the primary
        # kiosk decline surface — the client has to read `results[]` to know
        # which memberships exist and why the rest do not.
        207: {
            "model": MemberMembershipsStartResponse,
            "description": (
                "Partial — results[] carries the per-item split. A failed item "
                "is a bank DECLINE (`card declined: …`, nothing collected for "
                "that group), a definitive NON-COLLECTION (`not collected: …` "
                "— nobody refused, the charge needs authentication the member "
                "must complete; nothing collected, nothing booked) or, once "
                "this request's one-time charge already collected, a SYSTEM "
                "failure on the rest (`system failure: …`). Branch on the "
                "item, never on the status."
            ),
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update these members"},
        409: {
            "description": (
                f"Retried start replayed — original stands, or {BUSY_PAYER_409}"
            )
        },
        500: {
            "description": (
                "Total failure — nothing created and nothing charged "
                "(Stripe/sync). A system failure AFTER a charge collected is a "
                "207 instead, never this."
            )
        },
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
    """Start the request's memberships for the payer's family."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.payer_member_id, user_payload, staff_roles=STAFF
    )
    for item_member_id in {item.member_id for item in request.memberships}:
        await auth.verify_gym_employee_for_member(
            item_member_id, user_payload, staff_roles=STAFF
        )

    try:
        result = await memberships_service.start(request)
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
    except MembershipStartReplayError as exc:
        # Retried start detected as an idempotent replay — the original rows,
        # discounts, and charge stand. A conflict, not a server error: 409
        # (never auto-retried), matching the other billing conflicts here.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except WaiverGateError as exc:
        # A member hasn't signed a required waiver — blocked before any Stripe
        # call (nothing written/charged). 422 with the structured unsigned list
        # so the CRM routes the member straight to signing.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"message": str(exc), "unsigned": exc.unsigned},
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

    # Any failed charge group → 207 partial; all-created stays 201. The item's
    # `error` prefix says WHICH kind of failure it was — `card declined: ` (the
    # bank refused), `not collected: ` (nobody refused and the money still did
    # not arrive: the charge needs SCA / 3-D Secure authentication) or
    # `system failure: ` (our side broke after an earlier charge in this same
    # request already collected, so a 500 claiming "nothing created" would have
    # been a lie). The status alone can't carry that, which is exactly why
    # clients branch on the item.
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
        "Reprices a membership to its plan's active price (direct/synchronous). "
        "Returns the successor id (same id if already on the price — no-op)."
    ),
    responses={
        200: {"description": "Repriced; the successor membership id"},
        400: {"description": "Invalid request (cancelled / ended membership)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    """Reprice one membership to its plan's active price."""
    user_payload = auth.get_current_user(credentials)
    # STAFF: this moves ONE membership back onto its plan's CURRENT active
    # price (a correction of an outdated-price membership) — it is not a custom
    # amount, so it is member-money work front desk performs, like a charge or
    # a discount. Plan-wide bulk reprice (`reprice-plan`) stays OWNER_ADMIN.
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        new_item_id = await memberships_service.update_price(
            item_id=request.item_id,
            member_id=request.member_id,
            proration_behavior=request.proration_behavior,
        )
        return MemberMembershipsUpdatePriceResponse(item_id=new_item_id)
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
        "Upgrades a membership to a different plan (cross-plan, direct/synchronous). "
        "Charges the prorated difference when the new price is higher. "
        "Returns the successor id."
    ),
    responses={
        200: {"description": "Upgraded; the successor membership id"},
        400: {"description": "Invalid request (same plan / window / state)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    """Upgrade one membership to a different plan."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

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
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
    description="Dry-run of the upgrade endpoint. Returns due_now + recurring. Writes nothing.",
    responses={
        200: {"description": "Preview retrieved successfully"},
        400: {"description": "Invalid request (same plan / window / state)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await memberships_service.upgrade_preview(
            item_id=request.item_id,
            member_id=request.member_id,
            target_plan_id=request.target_plan_id,
            proration_behavior=request.proration_behavior,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
    "/cancel-one-time",
    response_model=MemberMembershipsCancelOneTimeResponse,
    summary="Cancel a one-time / trial membership early",
    description=(
        "Cancels a one-time/trial membership now — a MANUAL termination, so "
        "it writes cancel_date (end_date stays automatic-only: duration "
        "expiry + depletion auto-end). Pure DB write, no Stripe action. "
        "Recurring memberships are rejected — use DELETE / to cancel."
    ),
    responses={
        200: {"description": "Cancelled; the resolved cancel_date"},
        400: {"description": "Recurring / already ended / already cancelled"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Membership not found"},
    },
)
@inject
async def cancel_one_time_membership(
    request: MemberMembershipsCancelOneTimeRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
) -> MemberMembershipsCancelOneTimeResponse:
    """Cancel a one-time/trial membership early (manual termination)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        cancel_date = await memberships_service.cancel_one_time(
            request.item_id,
            request.member_id,
        )
        return MemberMembershipsCancelOneTimeResponse(
            cancel_date=cancel_date
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
            "Failed to cancel one-time membership: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel membership",
        ) from None


@member_memberships_router.post(
    "/reprice-plan",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=MemberMembershipsBatchRepriceResponse,
    summary="Batch-upgrade a plan's members to its active price",
    description=(
        "Batch-reprices every live membership on the plan to its active price. "
        "Returns task_id (null if nothing to upgrade); poll GET /api/v1/tasks/{task_id}."
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
    """Batch-reprice a plan's members to its active price."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

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
        "Dry-run of the start endpoint. Returns invoice split "
        "(one_time/due_now/recurring). Writes nothing."
    ),
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update these members"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
    await auth.verify_gym_employee_for_member(
        request.payer_member_id, user_payload, staff_roles=STAFF
    )
    for item_member_id in {item.member_id for item in request.memberships}:
        await auth.verify_gym_employee_for_member(
            item_member_id, user_payload, staff_roles=STAFF
        )

    try:
        return await memberships_service.preview_start(request)
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
    except WaiverGateError as exc:
        # Same gate as the real start (shared validation): surface the unsigned
        # waivers so the CRM blocks the preview/purchase until they're signed.
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"message": str(exc), "unsigned": exc.unsigned},
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
    description="Dry-run of cancel. Returns per-payer current→new subscription state.",
    responses={
        200: {"description": "Preview retrieved successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await memberships_service.preview_cancel_many(
            request.item_ids,
            request.member_id,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
        "Adds applied-discount rows then re-syncs Stripe. With preview=true, "
        "stages rows, returns invoice preview, then removes staged rows."
    ),
    responses={
        200: {"description": "Discounts added, or preview returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        return await memberships_service.add_discounts(
            item_id=request.item_id,
            member_id=request.member_id,
            discount_ids=request.discount_ids,
            idempotency_key=request.idempotency_key,
            preview=request.preview,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
        "Removes applied-discount rows then re-syncs Stripe. With preview=true, "
        "stages removal, returns invoice preview, then restores rows."
    ),
    responses={
        200: {"description": "Discounts removed, or preview returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        return await memberships_service.remove_discounts(
            item_id=request.item_id,
            member_id=request.member_id,
            applied_ids=request.applied_ids,
            idempotency_key=request.idempotency_key,
            preview=request.preview,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
        "Marks the membership's open Stripe invoice as paid out of band. "
        "Recurring memberships only. No card charged."
    ),
    responses={
        204: {"description": "Invoice marked paid successfully"},
        400: {"description": "Not recurring, no open invoice, or invalid state"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Membership not found"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        await memberships_service.mark_paid_cash(
            item_id=request.item_id,
            member_id=request.member_id,
            idempotency_key=request.idempotency_key,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
    "/retry-card",
    response_model=MemberMembershipsRetryCardResponse,
    summary="Retry the saved card on a recurring membership's open invoice",
    description=(
        "Charges the payer's saved default card for the membership's open "
        "Stripe invoice. Recurring memberships only. A collected charge is "
        "``paid`` (200); a DEFINITIVE non-collection is a result, not a server "
        "failure — ``declined`` (the bank refused) or ``not_collected`` (the "
        "payment needs authentication the member must complete), each with its "
        "reason in ``decline_reason`` (207)."
    ),
    responses={
        200: {"description": "Card charged — status=paid"},
        # Same model on the 207 so a client generator sees the not-collected
        # body, not just a description.
        207: {
            "model": MemberMembershipsRetryCardResponse,
            "description": (
                "Nothing collected; still overdue. status=declined (the bank "
                "refused — offer another card) or status=not_collected (nobody "
                "refused, but the payment needs extra authorization the member "
                "has to complete — collect another way). ``decline_reason`` "
                "carries the reason either way."
            ),
        },
        400: {"description": "Not recurring, no open invoice, or invalid state"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Membership not found"},
        409: {
            "description": (
                f"Membership is inside an unfinished task, or {BUSY_PAYER_409}"
            )
        },
        500: {"description": "Stripe / upstream error (no auto-retry)"},
    },
)
@inject
async def retry_membership_card(
    request: MemberMembershipsRetryCardRequest,
    response: Response,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    memberships_service: MemberMembershipsService = Depends(
        Provide[DependencyInjector.member_memberships_service]
    ),
    tasks_service: TasksService = Depends(
        Provide[DependencyInjector.tasks_service]
    ),
) -> MemberMembershipsRetryCardResponse:
    """Retry the payer's saved card on a recurring membership's open invoice."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await tasks_service.assert_memberships_not_in_task([request.item_id])
        await memberships_service.retry_card(
            item_id=request.item_id,
            member_id=request.member_id,
            idempotency_key=request.idempotency_key,
        )
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
    except stripe.CardError as exc:
        # A bank saying no is a definitive business OUTCOME, not a server
        # malfunction — so it is returned as a RESULT: 207 (a 2xx, never
        # auto-replayed by a proxy, so a money-moving retry is still safe)
        # carrying the decline in the body, exactly as the START path does with
        # its per-item ``failed`` entry. Reporting it as a 500 would bury real
        # outages in monitoring under ordinary declines.
        #
        # Staff need the DECLINE reason to know what to do next (expired ->
        # Update Card; insufficient -> tell the member). Stripe writes
        # ``user_message`` for end-user display, so surface that.
        logger.warning(
            "Retry card declined: item_id=%s, member_id=%s, code=%s",
            request.item_id,
            request.member_id,
            exc.code,
        )
        response.status_code = status.HTTP_207_MULTI_STATUS
        return MemberMembershipsRetryCardResponse(
            item_id=request.item_id,
            member_id=request.member_id,
            status=MemberMembershipsRetryCardStatus.declined,
            decline_reason=(exc.user_message or str(exc)),
        )
    except PaymentsNotCollectedError as exc:
        # NOT a decline and NOT a malfunction: Stripe accepted the pay call but
        # the invoice never reached ``paid`` because the off-session
        # PaymentIntent needs authentication (SCA / 3-D Secure) the member has
        # to complete. That is just as DEFINITIVE as a decline — "we could not
        # collect on this card, staff must act" — so it rides the same 2xx
        # RESULT contract (207, never auto-replayed by a proxy) instead of the
        # 500 an unrecognised Stripe failure gets, which would bury genuine
        # outages under an ordinary business outcome.
        #
        # Its OWN status, though: telling staff "declined" here would send them
        # to "try another card" when the bank never refused. The service's
        # message is written for the front desk, so surface it verbatim.
        #
        # MUST stay ABOVE the ``PaymentsStripeError`` arm — this is a subclass,
        # so the base arm would otherwise win and 500 it.
        logger.warning(
            "Retry card not collected (needs authentication): item_id=%s, "
            "member_id=%s",
            request.item_id,
            request.member_id,
        )
        response.status_code = status.HTTP_207_MULTI_STATUS
        return MemberMembershipsRetryCardResponse(
            item_id=request.item_id,
            member_id=request.member_id,
            status=MemberMembershipsRetryCardStatus.not_collected,
            decline_reason=str(exc),
        )
    except PaymentsStripeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        ) from None
    except Exception:
        # Any other Stripe/upstream failure — a 500, never a 502/503/504, so
        # no proxy replays a money-moving retry.
        logger.error(
            "Failed to retry the card on membership: item_id=%s, member_id=%s",
            request.item_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retry the card on membership",
        ) from None

    return MemberMembershipsRetryCardResponse(
        item_id=request.item_id,
        member_id=request.member_id,
        status=MemberMembershipsRetryCardStatus.paid,
    )


@member_memberships_router.post(
    "/charge-card",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Charge a member's card for an ad-hoc amount",
    description=(
        "Creates and pays a one-off Stripe invoice for amount_cents. "
        "paid_cash marks it out-of-band; payment_method_id bills a one-off "
        "card. A collected charge is 204; a DEFINITIVE non-collection (the "
        "payment needs authentication the member must complete) is a result, "
        "not a server failure — 207 with status=not_collected."
    ),
    responses={
        204: {"description": "Card charged successfully"},
        # Same shape retry-card's 207 declares, so a generated client sees the
        # body rather than just a description.
        207: {
            "model": MemberMembershipsChargeCardResponse,
            "description": (
                "Nothing collected. status=not_collected (nobody refused, but "
                "the payment needs extra authorization the member has to "
                "complete — collect another way); ``decline_reason`` carries "
                "the reason."
            ),
        },
        400: {"description": "Invalid request or gym mismatch"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to update this member"},
        404: {"description": "Member profile not found"},
        409: {"description": BUSY_PAYER_409.capitalize()},
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
) -> Response:
    """Charge a member's card (or mark as cash) for an ad-hoc amount."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

    try:
        await memberships_service.charge_card(request)
    except LockBusyError:
        # Busy payer -> 409 via the global handler; re-raised ABOVE the generic
        # arm because a `raise` inside an `except` escapes the whole `try`.
        raise
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
    except PaymentsNotCollectedError as exc:
        # Nobody refused and nothing arrived (SCA) — a DEFINITIVE outcome, so a
        # 207 RESULT carrying the reason, not the 500 a malfunction gets. Only
        # the success path stays 204/no body. MUST sit above the
        # PaymentsStripeError arm — this is a subclass, so the base arm would
        # otherwise win. Contract: CLAUDE.md "Billing / Stripe error status
        # codes".
        logger.warning(
            "Charge card not collected (needs authentication): member_id=%s, "
            "paid_by_member_id=%s, amount_cents=%s",
            request.member_id,
            request.paid_by_member_id,
            request.amount_cents,
        )
        return JSONResponse(
            status_code=status.HTTP_207_MULTI_STATUS,
            content=MemberMembershipsChargeCardResponse(
                member_id=request.member_id,
                paid_by_member_id=request.paid_by_member_id,
                status=MemberMembershipsRetryCardStatus.not_collected,
                decline_reason=str(exc),
            ).model_dump(mode="json"),
        )
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

    return Response(status_code=status.HTTP_204_NO_CONTENT)


@member_memberships_router.post(
    "/refund",
    response_model=MemberMembershipsRefundResponse,
    summary="Refund a prior charge (card via Stripe, or cash)",
    description=(
        "Refunds a prior charge (full or partial). "
        "Card charges via Stripe; cash recorded locally."
    ),
    responses={
        200: {"description": "Refund processed"},
        400: {"description": "Charge is not refundable or amount invalid"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized to manage this member (staff only)"},
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF
    )

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
