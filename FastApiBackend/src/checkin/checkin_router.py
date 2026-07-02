"""API routes for the checkin domain.

Single + batch check-in, sign-ups (reservations), the per-occurrence combined
roster, and the attendance streak.
"""

import logging
from datetime import date
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinRequest,
    BatchCheckinResponse,
)
from src.checkin.schema.checkin_schema import (
    AttendeeListResponse,
    CheckinRemoveResponse,
    CheckinRequest,
    CheckinResponse,
    StreakResponse,
)
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupRequest,
    SignupResponse,
)
from src.checkin.service.batch_checkin_service import BatchCheckinService
from src.checkin.service.checkin_attendees_service import (
    CheckinAttendeesService,
)
from src.checkin.service.checkin_class_resolver import (
    CheckinClassResolver,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_remover import CheckinRemover
from src.checkin.service.signup_service import SignupService
from src.checkin.service.streak_service import StreakService
from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

checkin_router = APIRouter(
    prefix="/api/v1",
    tags=["checkin"],
)


@checkin_router.post(
    "/checkin",
    response_model=CheckinResponse,
    summary="Check a member into a class instance",
    description=(
        "Addresses the occurrence by ``class_id`` + ``occurrence_date`` (the "
        "occurrence's ORIGINAL date) and resolves it against the class's "
        "schedule versions + exceptions, bumps ``last_class``, "
        "awards the class's points, and auto-ends trial / punch-card "
        "memberships once depleted. ``is_member = true`` (kiosk / member "
        "self-check-in) runs the strict gate — selects the best eligible "
        "membership with remaining capacity (trial -> one_time -> recurring) "
        "and, if none covers / the room is full, returns ``log_id = null`` "
        "with a ``skip_reason`` and writes nothing. ``is_member = false`` "
        "(default — staff / admin) records a clean check-in but, when the gate "
        "warns (no membership / out of classes / ineligible / over capacity), "
        "returns ``requires_confirmation = true`` with the ``warnings`` and "
        "writes nothing — resend with ``ignore_warnings = true`` to record it "
        "(best available / NULL attribution, warnings surfaced). Idempotent — a "
        "repeat for the same (member, occurrence) returns the existing log_id "
        "with ``already_checked_in = True``, consumes no capacity, and re-awards "
        "no points (``points_awarded`` echoes the original award)."
    ),
    responses={
        200: {"description": "Check-in result returned (recorded or skipped)"},
        400: {"description": "Not a valid occurrence on that date"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
        404: {"description": "Class not found"},
    },
)
@inject
async def checkin(
    request: CheckinRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    resolver: CheckinClassResolver = Depends(Provide[DependencyInjector.checkin_class_resolver]),
    member_gate: CheckinMemberGate = Depends(Provide[DependencyInjector.checkin_member_gate]),
    streak_service: StreakService = Depends(Provide[DependencyInjector.streak_service]),
) -> CheckinResponse:
    """Record attendance — resolve the occurrence, then run the member gate."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        resolved_class = await resolver.resolve(
            request.class_id, request.gym_id, request.occurrence_date
        )
        result = await member_gate.checkin_member(
            resolved_class,
            request.member_id,
            request.is_member,
            request.ignore_warnings,
        )
        # Fold in the member's streak (after this check-in) so the caller needn't
        # make a second GET /streak call.
        if result.log_id is not None:
            result.class_streak_weeks = await streak_service.get_streak(
                request.member_id, request.gym_id
            )
        return result
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
            "Check-in failed: member_id=%s, class_id=%s, occurrence_date=%s",
            request.member_id,
            request.class_id,
            request.occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record check-in",
        ) from None


@checkin_router.delete(
    "/checkin",
    response_model=CheckinRemoveResponse,
    summary="Remove one member's check-in from a class occurrence",
    description=(
        "Reverses one member's check-in on the occurrence addressed by "
        "``class_id`` + ``occurrence_date``: deletes their attendance row, claws "
        "back the class's points (floored at 0), drops a ``class_attended`` "
        "activity, and — when the removal drops a trial / punch-card pack back "
        "below capacity — reverses the auto-end (clears the pack's "
        "``end_date``). The occurrence itself is kept (the class still "
        "happened). A member who was not checked in (or an occurrence never "
        "materialized) returns ``removed = false`` with a 200. Admin / owner "
        "only."
    ),
    responses={
        200: {"description": "Removal result (removed true / false)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def remove_checkin(
    member_id: UUID,
    gym_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    remover: CheckinRemover = Depends(Provide[DependencyInjector.checkin_remover]),
) -> CheckinRemoveResponse:
    """Reverse one member's check-in (staff)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        return await remover.remove(class_id, gym_id, occurrence_date, member_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Remove check-in failed: member_id=%s, class_id=%s, occurrence_date=%s",
            member_id,
            class_id,
            occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to remove check-in",
        ) from None


@checkin_router.post(
    "/signup",
    response_model=SignupResponse,
    summary="Reserve a member a spot on a class occurrence",
    description=(
        "Reserves ``member_id`` a spot on the occurrence addressed by "
        "``class_id`` + ``occurrence_date`` (the occurrence's ORIGINAL date). "
        "A sign-up is a reservation, NOT attendance — ``member_attendance`` "
        "is still only written by a check-in. The occurrence is validated "
        "before capacity is checked: rejected with 'Class has been deleted' "
        "/ 'Class is not active' for a soft-deleted / inactive class, "
        "'Not a class occurrence on that date' / 'This class is cancelled "
        "that day' when ``occurrence_date`` isn't a real, non-cancelled "
        "occurrence of the class. Capacity is reserving: rejected with "
        "'Class is full' when the occurrence's effective ``max_capacity`` is "
        "already reached by the DISTINCT count of members signed-up OR "
        "attended (NULL capacity = unlimited, never blocks). Idempotent — "
        "signing up twice for the same (member, occurrence) returns the "
        "existing ``signup_id`` with ``already_signed_up = true`` and "
        "consumes no extra capacity. Both staff (any employee of the gym) "
        "and the member themselves may call this."
    ),
    responses={
        200: {"description": "Sign-up created (or an idempotent repeat)"},
        400: {
            "description": (
                "Class is full / deleted / inactive, or the date isn't a "
                "real, non-cancelled occurrence of the class"
            )
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
        404: {"description": "Class or gym not found"},
    },
)
@inject
async def signup(
    request: SignupRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(Provide[DependencyInjector.signup_service]),
) -> SignupResponse:
    """Reserve a member a spot on a class occurrence."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await signup_service.create(
            request.member_id,
            request.gym_id,
            request.class_id,
            request.occurrence_date,
        )
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
            "Sign-up failed: member_id=%s, class_id=%s, occurrence_date=%s",
            request.member_id,
            request.class_id,
            request.occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record sign-up",
        ) from None


@checkin_router.delete(
    "/signup",
    response_model=SignupRemoveResponse,
    summary="Cancel a member's sign-up for a class occurrence",
    responses={
        200: {"description": "Removal result (removed true / false)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def remove_signup(
    member_id: UUID,
    gym_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(Provide[DependencyInjector.signup_service]),
) -> SignupRemoveResponse:
    """Cancel a member's sign-up (staff or the member themselves)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await signup_service.remove(member_id, gym_id, class_id, occurrence_date)
    except Exception:
        logger.error(
            "Remove sign-up failed: member_id=%s, class_id=%s, occurrence_date=%s",
            member_id,
            class_id,
            occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to remove sign-up",
        ) from None


@checkin_router.post(
    "/checkin/batch",
    summary="Check many members into one class occurrence (staff batch)",
    description=(
        "Resolves the occurrence ONCE (by ``class_id`` + ``occurrence_date`` "
        "— the ORIGINAL date — in the body; a pure read, nothing written), "
        "then runs the per-member check-in gate over each (de-duped) member. "
        "One bad member never sinks the batch — its result is a ``failed`` item. "
        "Returns **207 Multi-Status** with a per-member split (``checked_in`` / "
        "``already_checked_in`` / ``skipped`` / ``needs_confirmation`` / "
        "``failed``). A total failure (every member failed) is **500**; an "
        "invalid occurrence is **400 / 404** before any member is processed. "
        "``is_member`` applies to every member: ``false`` (default — a staff "
        "batch) records a clean member and holds a warned one as "
        "``needs_confirmation`` (not recorded) unless ``ignore_warnings = true`` "
        "overrides; ``true`` runs the strict kiosk gate per member, skipping the "
        "uncovered / over-capacity. Admin/owner only."
    ),
    responses={
        207: {
            "model": BatchCheckinResponse,
            "description": (
                "Per-member results returned (any mix of checked_in / "
                "already_checked_in / skipped / needs_confirmation / failed)"
            ),
        },
        400: {"description": "Not a valid occurrence on that date"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
        500: {"description": "Batch check-in failed for every member"},
    },
)
@inject
async def checkin_batch(
    request: BatchCheckinRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    batch_service: BatchCheckinService = Depends(
        Provide[DependencyInjector.batch_checkin_service]
    ),
) -> JSONResponse:
    """Batch staff check-in — 207 on any processed mix, 500 on total failure."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        response, all_failed = await batch_service.batch_checkin(
            request.class_id,
            request.gym_id,
            request.occurrence_date,
            request.member_ids,
            request.is_member,
            request.ignore_warnings,
        )
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
            "Batch check-in failed: gym_id=%s, class_id=%s, occurrence_date=%s",
            request.gym_id,
            request.class_id,
            request.occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record batch check-in",
        ) from None

    if all_failed:
        # Total failure — 500 (never 207); the per-item reasons are logged but a
        # whole-batch failure must not look like a success to the caller.
        logger.error(
            "Batch check-in failed for every member: gym_id=%s, class_id=%s, occurrence_date=%s",
            request.gym_id,
            request.class_id,
            request.occurrence_date,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Batch check-in failed for every member",
        )

    return JSONResponse(
        status_code=status.HTTP_207_MULTI_STATUS,
        content=jsonable_encoder(response),
    )


@checkin_router.get(
    "/checkin/attendees",
    response_model=AttendeeListResponse,
    summary="List the combined roster (signed-up + attended) of an occurrence",
    description=(
        "Returns the combined roster for the occurrence addressed by "
        "(``class_id``, ``occurrence_date`` — the occurrence's ORIGINAL "
        "date): every member who signed up (``class_signups``) OR attended "
        "(``member_attendance``), each flagged ``signed_up`` / ``attended`` "
        "— ``member_id`` + ``full_name`` + the attributed ``plan_id`` / "
        "``item_id`` (NULL when not attended). A signed-up-only member can "
        "appear even when nobody has checked in yet (a future occurrence "
        "can carry sign-ups with no attendance at all). Gym-employee gated."
    ),
    responses={
        200: {"description": "Roster returned (possibly empty)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Gym not found"},
    },
)
@inject
async def list_attendees(
    gym_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    attendees_service: CheckinAttendeesService = Depends(
        Provide[DependencyInjector.checkin_attendees_service]
    ),
) -> AttendeeListResponse:
    """The members who attended one occurrence (empty when unmaterialized)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await attendees_service.list_attendees(gym_id, class_id, occurrence_date)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Attendee list failed: gym_id=%s, class_id=%s, occurrence_date=%s",
            gym_id,
            class_id,
            occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list attendees",
        ) from None


@checkin_router.get(
    "/streak",
    response_model=StreakResponse,
    summary="Get a member's class attendance streak",
    responses={
        200: {"description": "Streak retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def get_streak(
    member_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    streak_service: StreakService = Depends(Provide[DependencyInjector.streak_service]),
) -> StreakResponse:
    """Weeks of consecutive class attendance."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        weeks = await streak_service.get_streak(member_id, gym_id)
    except Exception:
        logger.error(
            "Streak query failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve streak",
        ) from None

    return StreakResponse(member_id=member_id, class_streak_weeks=weeks)
