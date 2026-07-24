"""API routes for the checkin domain.

Single + batch check-in, sign-ups (reservations), the per-occurrence combined
roster, and the attendance streak.

**Error status AND the machine-readable ``code`` are decided BY EXCEPTION
TYPE, never by the message text.** The domain raises the typed errors in
``checkin_exceptions``, each of which carries its own ``status_code`` +
``code``; ``CheckinClassNotFoundError`` is the only one that 404s, every
other ``CheckinError`` is a 400 (including "not an occurrence of this class",
which these endpoints have documented as a 400 since they shipped —
occurrences are computed, so a bad slot is a bad address, not a missing
resource). Rewording a message can no longer move a status code.

Every handler below re-raises a ``CheckinError`` untouched so the ONE global
formatter (``_handle_checkin_error`` in ``src/main.py``) writes the body:
``{"detail": "<prose>", "code": "<stable_code>"}`` — ``code`` a SIBLING key,
``detail`` always a plain string. A ``raise`` inside an ``except`` clause
propagates out of the whole ``try``, so the sibling ``except Exception ->
500`` arm below it never re-catches the re-raised error.

Because every one of them subclasses ``ValueError``, the trailing generic
``except ValueError`` still catches an unmapped FOREIGN domain error as a 400
(bad input) instead of letting it fall to a 500 — that arm emits no ``code``.
"""

import logging
from datetime import date, time
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.checkin.checkin_exceptions import CheckinError
from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinRequest,
    BatchCheckinResponse,
)
from src.checkin.schema.checkin_error_schema import CheckinErrorResponse
from src.checkin.schema.checkin_history_schema import (
    MemberClassHistoryResponse,
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
from src.checkin.service.checkin_history_service import (
    CheckinHistoryService,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_remover import CheckinRemover
from src.checkin.service.signup_service import SignupService
from src.checkin.service.streak_service import StreakService
from src.core.dependencies import DependencyInjector
from src.shared.auth import ALL_EMPLOYEES, STAFF, Auth, security
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)

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
        "Addresses the occurrence by ``class_id`` + ``occurrence_date`` + "
        "``occurrence_time`` (the occurrence's ORIGINAL slot — date + time) "
        "and resolves it against the class's schedule versions + exceptions, "
        "bumps ``last_class``, "
        "awards the class's points, and auto-ends trial / punch-card "
        "memberships once depleted. Staff-only (``STAFF`` at the member's "
        "gym) — ``is_member`` is a staff-selected MODE, not a caller "
        "identity. ``is_member = true`` (kiosk mode) runs the strict gate — "
        "selects the best eligible "
        "membership with remaining capacity (trial -> one_time -> recurring) "
        "and, if none covers / the room is full, returns ``log_id = null`` "
        "with a ``skip_reason`` and writes nothing. ``is_member = false`` "
        "(default — staff / admin) records a clean check-in but, when the gate "
        "warns (no membership / out of classes / ineligible / over capacity / "
        "unsigned waiver / overdue), "
        "returns ``requires_confirmation = true`` with the ``warnings`` and "
        "writes nothing — resend with ``ignore_warnings = true`` to record it "
        "(best available / NULL attribution, warnings surfaced). Idempotent — a "
        "repeat for the same (member, occurrence) returns the existing log_id "
        "with ``already_checked_in = True``, consumes no capacity, and re-awards "
        "no points (``points_awarded`` echoes the original award)."
    ),
    responses={
        200: {"description": "Check-in result returned (recorded or skipped)"},
        400: {
            "model": CheckinErrorResponse,
            "description": (
                "Not a valid occurrence on that date / class deleted or "
                "inactive / check-in not open yet. ``code`` is the stable "
                "discriminator; ``detail`` is prose"
            ),
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
        404: {
            "model": CheckinErrorResponse,
            "description": "Class not found (``code`` = class_not_found)",
        },
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
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF,
        gym_id=request.gym_id,
    )

    try:
        resolved_class = await resolver.resolve(
            request.class_id,
            request.gym_id,
            request.occurrence_date,
            request.occurrence_time,
        )
        result = await member_gate.checkin_member(
            resolved_class,
            request.member_id,
            request.is_member,
            request.ignore_warnings,
        )
        # Fold in the member's streak + current-week strip (after this
        # check-in) so the caller needn't make a second GET /streak call.
        if result.log_id is not None:
            streak = await streak_service.get_streak_details(
                request.member_id, request.gym_id
            )
            result.class_streak_weeks = streak.weeks
            result.current_week_days = streak.current_week_days
        return result
    except CheckinError:
        # Re-raised untouched: the global handler reads the status + the
        # stable ``code`` off the type. This arm exists ONLY so the
        # `except Exception` below can't swallow it — a `raise` inside an
        # `except` clause propagates out of the whole `try`.
        raise
    except ValueError as exc:
        # An unmapped/foreign ValueError is bad input, not a 5xx (no code).
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
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
        "``class_id`` + ``occurrence_date`` + ``occurrence_time`` (the "
        "original slot — date + time): deletes their attendance row, claws "
        "back the class's points (floored at 0), drops a ``class_attended`` "
        "activity, and — when the removal drops a trial / punch-card pack back "
        "below capacity — reverses the auto-end (clears the pack's "
        "``end_date``). The occurrence itself is kept (the class still "
        "happened). A member who was not checked in returns "
        "``removed = false`` with a 200. Staff only "
        "(owner/admin/front_desk)."
    ),
    responses={
        200: {"description": "Removal result (removed true / false)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {
            "model": CheckinErrorResponse,
            "description": "Class not found (``code`` = class_not_found)",
        },
        500: {"description": "Failed to remove the check-in"},
    },
)
@inject
async def remove_checkin(
    member_id: UUID,
    gym_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    occurrence_time: time,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    remover: CheckinRemover = Depends(Provide[DependencyInjector.checkin_remover]),
) -> CheckinRemoveResponse:
    """Reverse one member's check-in (staff)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, STAFF)

    try:
        return await remover.remove(
            class_id, gym_id, occurrence_date, occurrence_time, member_id
        )
    except CheckinError:
        # Re-raised for the global formatter (404 / class_not_found is the
        # only rejection the remover raises). No blanket `except ValueError`
        # here on purpose: this handler used to 404 on ANY ValueError, and
        # pydantic's ValidationError IS a ValueError — a malformed
        # CheckinRemoveResponse would have surfaced as a 404 carrying a raw
        # validation dump instead of a logged 500.
        raise
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
        "``class_id`` + ``occurrence_date`` + ``occurrence_time`` (the "
        "occurrence's ORIGINAL slot — date + time). "
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
        "consumes no extra capacity. Staff-only — the caller must hold a "
        "``STAFF`` role at the member's gym."
    ),
    responses={
        200: {"description": "Sign-up created (or an idempotent repeat)"},
        400: {
            "model": CheckinErrorResponse,
            "description": (
                "Class is full / deleted / inactive, or the date isn't a "
                "real, non-cancelled occurrence of the class. ``code`` is "
                "the stable discriminator; ``detail`` is prose"
            ),
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
        404: {
            "model": CheckinErrorResponse,
            "description": "Class not found (``code`` = class_not_found)",
        },
    },
)
@inject
async def signup(
    request: SignupRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(Provide[DependencyInjector.signup_service]),
    profile_refresh_runner: MemberVideoProfileRefreshRunner = Depends(
        Provide[DependencyInjector.member_video_profile_refresh_runner]
    ),
) -> SignupResponse:
    """Reserve a member a spot on a class occurrence."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        request.member_id, user_payload, staff_roles=STAFF,
        gym_id=request.gym_id,
    )

    try:
        result = await signup_service.create(
            request.member_id,
            request.gym_id,
            request.class_id,
            request.occurrence_date,
            request.occurrence_time,
        )
        # A class booking is fresh taste signal — fire a best-effort profile
        # refresh (gated to once per cooldown; never fails the booking). The
        # trigger is router-level composition so SignupService stays decoupled
        # from the videos domain.
        profile_refresh_runner.start(request.member_id, request.gym_id)
        return result
    except CheckinError:
        # Re-raised for the global formatter (status + code off the type):
        # class not found -> 404, every other sign-up rejection (deleted /
        # inactive class, not an occurrence, cancelled day, class full) -> 400.
        raise
    except ValueError as exc:
        # An unmapped/foreign ValueError is bad input, not a 5xx.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
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
    occurrence_time: time,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(Provide[DependencyInjector.signup_service]),
) -> SignupRemoveResponse:
    """Cancel a member's sign-up (staff of the member's gym)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF, gym_id=gym_id
    )

    try:
        return await signup_service.remove(
            member_id, gym_id, class_id, occurrence_date, occurrence_time
        )
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
        "+ ``occurrence_time`` — the ORIGINAL slot, date + time — in the "
        "body; a pure read, nothing written), "
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
        "uncovered / over-capacity. Staff only (owner/admin/front_desk)."
    ),
    responses={
        207: {
            "model": BatchCheckinResponse,
            "description": (
                "Per-member results returned (any mix of checked_in / "
                "already_checked_in / skipped / needs_confirmation / failed)"
            ),
        },
        400: {
            "model": CheckinErrorResponse,
            "description": (
                "Not a valid occurrence on that date / class deleted or "
                "inactive / check-in not open yet. ``code`` is the stable "
                "discriminator; ``detail`` is prose"
            ),
        },
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {
            "model": CheckinErrorResponse,
            "description": "Class not found (``code`` = class_not_found)",
        },
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
    await auth.verify_roles(request.gym_id, user_payload, STAFF)
    # A member from another gym cannot be stamped in: member_attendance's
    # composite FK (member_id, gym_id) -> members(member_id, gym_id) rejects
    # the write, and the batch isolates that per member (a failed item in the
    # 207), so a foreign/unknown id never corrupts the batch or leaks a
    # cross-gym row. No whole-batch gym pre-check — it would break the 207
    # per-item contract by failing every member for one bad id.

    try:
        response, all_failed = await batch_service.batch_checkin(
            request.class_id,
            request.gym_id,
            request.occurrence_date,
            request.occurrence_time,
            request.member_ids,
            request.is_member,
            request.ignore_warnings,
        )
    except CheckinError:
        # The batch resolves the occurrence ONCE before any per-member work, so
        # these are whole-request failures. Re-raised for the global formatter:
        # class not found -> 404; deleted / inactive class, not an occurrence
        # of this class, check-in not open yet -> 400.
        raise
    except ValueError as exc:
        # An unmapped/foreign ValueError is bad input, not a 5xx.
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
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
        "(``class_id``, ``occurrence_date``, ``occurrence_time`` — the "
        "occurrence's ORIGINAL slot, date + time): every member who signed "
        "up (``class_signups``) OR attended "
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
        500: {"description": "Failed to read the roster"},
    },
)
@inject
async def list_attendees(
    gym_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    occurrence_time: time,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    attendees_service: CheckinAttendeesService = Depends(
        Provide[DependencyInjector.checkin_attendees_service]
    ),
) -> AttendeeListResponse:
    """Everyone signed up or attended for one occurrence (may be empty)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, ALL_EMPLOYEES)

    try:
        return await attendees_service.list_attendees(
            gym_id, class_id, occurrence_date, occurrence_time
        )
    # No `except ValueError` arm: this is a pure read that raises no domain
    # error at all (an unknown gym / class / slot is an EMPTY roster, not a
    # rejection), so the blanket ValueError -> 404 that used to sit here could
    # only ever fire on an INTERNAL failure — and pydantic's ValidationError
    # subclasses ValueError, so a malformed roster row surfaced as a 404
    # carrying a raw validation dump. It is a 500 now, logged with the trace.
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
    "/checkin/history",
    response_model=MemberClassHistoryResponse,
    summary="A member's class history (reservations, attendance, no-shows)",
    description=(
        "The member-page history card's feed: the member's OPEN "
        "reservations (occurrences not yet ended, soonest first, "
        "unpaginated) plus a newest-first PAGE of their history — attended "
        "occurrences and no-shows (a reservation whose occurrence ended "
        "with no matching check-in). Staff-only — the caller must hold a "
        "``STAFF`` role at the member's gym."
    ),
    responses={
        200: {"description": "History retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def get_member_class_history(
    member_id: UUID,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    limit: int = 20,
    offset: int = 0,
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    history_service: CheckinHistoryService = Depends(
        Provide[DependencyInjector.checkin_history_service]
    ),
) -> MemberClassHistoryResponse:
    """One member's reservations + attended + no-show feed."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        return await history_service.get_history(
            member_id, gym_id, limit=min(max(limit, 1), 100), offset=max(offset, 0)
        )
    except Exception:
        logger.error(
            "Class-history query failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve class history",
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
    await auth.verify_gym_employee_for_member(
        member_id, user_payload, staff_roles=STAFF
    )

    try:
        streak = await streak_service.get_streak_details(member_id, gym_id)
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

    return StreakResponse(
        member_id=member_id,
        class_streak_weeks=streak.weeks,
        current_week_days=streak.current_week_days,
    )
