"""API routes for the checkin domain.

Single + batch check-in, the per-occurrence attendee list, and the attendance
streak.
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
    CheckinRequest,
    CheckinResponse,
    StreakResponse,
)
from src.checkin.service.batch_checkin_service import BatchCheckinService
from src.checkin.service.checkin_attendees_service import (
    CheckinAttendeesService,
)
from src.checkin.service.checkin_service import CheckinService
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
        "Addresses the occurrence by ``class_id`` + ``occurrence_date`` and "
        "lazily materializes the ``class_history`` row, bumps ``last_class``, "
        "awards the class's points, and auto-ends trial / punch-card "
        "memberships once depleted. ``is_member = true`` (kiosk / member "
        "self-check-in) runs the strict gate — selects the best eligible "
        "membership with remaining capacity (trial -> one_time -> recurring) "
        "and, if none covers / the room is full, returns ``log_id = null`` "
        "with a ``skip_reason`` and writes nothing. ``is_member = false`` "
        "(default — staff / admin) ALWAYS records: it attributes to the "
        "member's best available membership (eligibility + remaining count "
        "ignored; NULL plan/item when the member has none) and returns any gate "
        "conditions in ``warnings``. Idempotent — a repeat for the same "
        "(member, occurrence) returns the existing log_id with "
        "``already_checked_in = True``, consumes no capacity, and awards no "
        "points."
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
    checkin_service: CheckinService = Depends(
        Provide[DependencyInjector.checkin_service]
    ),
) -> CheckinResponse:
    """Record attendance."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await checkin_service.checkin(request)
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


@checkin_router.post(
    "/checkin/batch",
    summary="Check many members into one class occurrence (staff batch)",
    description=(
        "Resolves + materializes the occurrence's single ``class_history`` row "
        "ONCE (by ``class_id`` + ``occurrence_date`` in the body), then runs "
        "the per-member check-in gate over each (de-duped) member. One bad "
        "member never sinks the batch — its result is a ``failed`` item. "
        "Returns **207 Multi-Status** with a per-member split (``checked_in`` / "
        "``already_checked_in`` / ``skipped`` / ``failed``). A total failure "
        "(every member failed) is **500**; an invalid occurrence is **400 / "
        "404** before any member is processed. ``is_member`` applies to every "
        "member: ``false`` (default — a staff batch) records each member with "
        "``warnings``; ``true`` runs the strict kiosk gate per member, skipping "
        "the uncovered / over-capacity. Admin/owner only."
    ),
    responses={
        207: {
            "model": BatchCheckinResponse,
            "description": (
                "Per-member results returned (any mix of checked_in / "
                "already_checked_in / skipped / failed)"
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
            "Batch check-in failed for every member: gym_id=%s, class_id=%s, "
            "occurrence_date=%s",
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
    summary="List the members who attended a class occurrence",
    description=(
        "Resolves the materialized ``class_history`` row for the (``class_id``, "
        "gym-local ``occurrence_date``) and returns the members who attended it "
        "— ``member_id`` + ``full_name`` + the attributed ``plan_id`` / "
        "``item_id`` (NULL for a no-membership staff check-in). An occurrence "
        "that was never materialized (no check-ins yet) returns "
        "``class_history_id = null`` with an empty list. Gym-employee gated."
    ),
    responses={
        200: {"description": "Attendee list returned (possibly empty)"},
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
        return await attendees_service.list_attendees(
            gym_id, class_id, occurrence_date
        )
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
    streak_service: StreakService = Depends(
        Provide[DependencyInjector.streak_service]
    ),
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
