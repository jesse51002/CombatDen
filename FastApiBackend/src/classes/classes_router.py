"""API routes for the classes domain."""

import logging
from datetime import date
from typing import Annotated, NoReturn
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.classes.schema.classes_crud_schema import (
    ClassInstanceExceptionListResponse,
    ClassInstanceExceptionResponse,
    ClassInstanceExceptionUpsertRequest,
    ClassRangeExceptionCreateRequest,
    ClassRangeExceptionListResponse,
    ClassRangeExceptionResponse,
    EffectiveClassInstanceListResponse,
    GymClassCreateRequest,
    GymClassListResponse,
    GymClassResponse,
    GymClassUpdateRequest,
)
from src.classes.schema.classes_undo_schema import (
    OccurrenceCancelResponse,
    OccurrenceRescheduleRequest,
    OccurrenceRescheduleResponse,
)
from src.classes.service.classes_crud_service import ClassesCrudService
from src.classes.service.classes_exceptions_service import (
    ClassesExceptionsService,
)
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)
from src.classes.service.classes_undo_service import (
    ClassesUndoService,
    RescheduleConflictError,
)
from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

classes_router = APIRouter(
    prefix="/api/v1/classes",
    tags=["classes"],
)


# ---------------------------------------------------------------------------
# Occurrence un-occur (cancel) + reschedule — Phase 6. Admin/owner gated on the
# caller-supplied gym_id (the same direct ``verify_gym_admin_or_owner`` wiring
# the batch check-in uses); the service validates the class belongs to that gym
# (404 otherwise). Billing-adjacent: cancel deletes attendance + may clear an
# auto-end end_date, never claws back points.
# ---------------------------------------------------------------------------


def _raise_for_undo_value_error(msg: str) -> NoReturn:
    """Map a service ValueError message to its HTTP status (never 5xx-retryable).

    ``not found`` -> 404; every other validation message -> 400. A reschedule
    collision is raised as ``RescheduleConflictError`` (mapped to 409 at the
    call site), never as a ValueError, so it never reaches here.
    """
    lowered = msg.lower()
    code = (
        status.HTTP_404_NOT_FOUND
        if "not found" in lowered
        else status.HTTP_400_BAD_REQUEST
    )
    raise HTTPException(status_code=code, detail=msg) from None


@classes_router.delete(
    "/{class_id}/occurrences/{occurrence_date}",
    response_model=OccurrenceCancelResponse,
    summary="Cancel (un-occur) a single class occurrence",
    description=(
        "Un-occurs the occurrence on ``occurrence_date``: deletes its "
        "materialized ``class_history`` row and ``member_attendance`` (if any), "
        "reverses the auto-end on trial / one_time packs that drop back below "
        "capacity, and writes the cancelled instance exception so the day never "
        "re-materializes. Points are NEVER clawed back. When nothing was "
        "materialized yet, only the cancelled exception is written "
        "(``class_history_id = null``). Admin/owner only."
    ),
    responses={
        200: {"description": "Occurrence cancelled"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found for this gym"},
    },
)
@inject
async def cancel_occurrence(
    class_id: UUID,
    occurrence_date: date,
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    undo_service: ClassesUndoService = Depends(
        Provide[DependencyInjector.classes_undo_service]
    ),
) -> OccurrenceCancelResponse:
    """Un-occur a single class occurrence (admin/owner)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        return await undo_service.cancel_occurrence(
            class_id, gym_id, occurrence_date
        )
    except ValueError as exc:
        _raise_for_undo_value_error(str(exc))
    except Exception:
        logger.error(
            "Failed to cancel occurrence: class_id=%s, gym_id=%s, date=%s",
            class_id,
            gym_id,
            occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel occurrence",
        ) from None


@classes_router.post(
    "/{class_id}/occurrences/{occurrence_date}/reschedule",
    response_model=OccurrenceRescheduleResponse,
    summary="Reschedule a single class occurrence to any date",
    description=(
        "Moves the occurrence on ``occurrence_date`` to ``new_date`` (any date — "
        "past, today, or future) by upserting the instance exception's "
        "``new_date``. Attendance follows the move: a FUTURE target wipes the "
        "occurrence's check-ins (points clawed back); a today / PAST target "
        "keeps them, re-dated onto the new day — all in one transaction. "
        "Rejected with 409 only when the exact target instant (new_date + start "
        "time) is already taken by a non-cancelled occurrence (landing on a busy "
        "day at a different time is allowed). Admin/owner only."
    ),
    responses={
        200: {"description": "Occurrence rescheduled"},
        400: {"description": "Invalid request (not an occurrence)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found for this gym"},
        409: {"description": "Target instant already occupied"},
    },
)
@inject
async def reschedule_occurrence(
    class_id: UUID,
    occurrence_date: date,
    request: OccurrenceRescheduleRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    undo_service: ClassesUndoService = Depends(
        Provide[DependencyInjector.classes_undo_service]
    ),
) -> OccurrenceRescheduleResponse:
    """Reschedule a single occurrence to a later date (admin/owner)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        return await undo_service.reschedule_occurrence(
            class_id, request.gym_id, occurrence_date, request.new_date
        )
    except RescheduleConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except ValueError as exc:
        _raise_for_undo_value_error(str(exc))
    except Exception:
        logger.error(
            "Failed to reschedule occurrence: class_id=%s, gym_id=%s, date=%s",
            class_id,
            request.gym_id,
            occurrence_date,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reschedule occurrence",
        ) from None


# ---------------------------------------------------------------------------
# Class CRUD + exceptions + the schedule board.
#
# Auth: reads are gym-employee gated via ``verify_gym_employee``; writes
# (create / update / soft-delete / exception upsert + range) are gated to
# admin-or-owner via ``verify_gym_admin_or_owner`` — the same read/write split
# the sibling gym-config CRUD domains (rewards / discounts / plans) use, and
# the API-layer mirror of the DB's ``is_gym_admin_or_owner`` RLS function.
# Trainers may read gym config but may not mutate it.
#
# Static sub-paths (``/instances``) are declared BEFORE ``/{class_id}`` so they
# are never captured by the UUID path param.
# ---------------------------------------------------------------------------


@classes_router.get(
    "",
    response_model=GymClassListResponse,
    summary="List a gym's classes",
    responses={
        200: {"description": "Classes listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_classes(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
    include_inactive: bool = False,
) -> GymClassListResponse:
    """List non-deleted classes for a gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await crud_service.list_classes(
            gym_id, include_inactive=include_inactive
        )
    except Exception:
        logger.error("Failed to list classes: gym_id=%s", gym_id, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list classes",
        ) from None


@classes_router.post(
    "",
    response_model=GymClassResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a class",
    responses={
        201: {"description": "Class created"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_class(
    request: GymClassCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
) -> GymClassResponse:
    """Create a gym class."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        return await crud_service.create_class(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create class: gym_id=%s", request.gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create class",
        ) from None


@classes_router.get(
    "/instances",
    response_model=EffectiveClassInstanceListResponse,
    summary="The schedule board: effective dated occurrences in a window",
    description=(
        "Expands every non-deleted class + its exceptions over "
        "``[start_date, end_date]`` (cancelled days included, flagged) and "
        "enriches each occurrence with the resolved instructor name, the "
        "instance/range-exception flags, and the recorded attendance count."
    ),
    responses={
        200: {"description": "Schedule board returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_effective_instances(
    gym_id: UUID,
    start_date: date,
    end_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    reader_service: ClassesScheduleReaderService = Depends(
        Provide[DependencyInjector.classes_schedule_reader_service]
    ),
) -> EffectiveClassInstanceListResponse:
    """The schedule board for a gym across a date window."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await reader_service.list_effective_instances(
            gym_id, start_date, end_date
        )
    except Exception:
        logger.error(
            "Failed to build schedule board: gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build schedule board",
        ) from None


@classes_router.post(
    "/{class_id}/exceptions/instance",
    response_model=ClassInstanceExceptionResponse,
    summary="Upsert a single-date class exception",
    description=(
        "Inserts or replaces the override for one occurrence (unique per "
        "class + original_date). A reschedule (``new_date``, any date) moves the "
        "occurrence and its attendance atomically — a FUTURE target wipes the "
        "check-ins (points clawed back), a today / PAST target keeps them "
        "re-dated — and is rejected with 409 only when the exact target instant "
        "(new_date + start time) is already taken by a non-cancelled occurrence."
    ),
    responses={
        200: {"description": "Exception upserted"},
        400: {"description": "Invalid exception"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
        409: {"description": "Reschedule target instant already occupied"},
    },
)
@inject
async def upsert_instance_exception(
    class_id: UUID,
    request: ClassInstanceExceptionUpsertRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
    exceptions_service: ClassesExceptionsService = Depends(
        Provide[DependencyInjector.classes_exceptions_service]
    ),
) -> ClassInstanceExceptionResponse:
    """Upsert a single-date instance exception."""
    user_payload = auth.get_current_user(credentials)
    existing = await _resolve_class_for_auth(
        crud_service, auth, class_id, user_payload, require_admin_or_owner=True
    )

    try:
        return await exceptions_service.upsert_instance_exception(
            class_id, existing.gym_id, request
        )
    except RescheduleConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to upsert instance exception: class_id=%s",
            class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to upsert instance exception",
        ) from None


@classes_router.get(
    "/{class_id}/exceptions/instance",
    response_model=ClassInstanceExceptionListResponse,
    summary="List a class's single-date exceptions in a window",
    responses={
        200: {"description": "Instance exceptions listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def list_instance_exceptions(
    class_id: UUID,
    start_date: date,
    end_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
    exceptions_service: ClassesExceptionsService = Depends(
        Provide[DependencyInjector.classes_exceptions_service]
    ),
) -> ClassInstanceExceptionListResponse:
    """List instance exceptions for a class within a window."""
    user_payload = auth.get_current_user(credentials)
    await _resolve_class_for_auth(crud_service, auth, class_id, user_payload)

    try:
        return await exceptions_service.list_instance_exceptions(
            class_id, start_date, end_date
        )
    except Exception:
        logger.error(
            "Failed to list instance exceptions: class_id=%s",
            class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list instance exceptions",
        ) from None


@classes_router.post(
    "/{class_id}/exceptions/range",
    response_model=ClassRangeExceptionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a continuous-range class exception",
    description=(
        "Cancels the class across a date range and/or substitutes the "
        "instructor (one of the two is required)."
    ),
    responses={
        201: {"description": "Range exception created"},
        400: {"description": "Invalid exception"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def create_range_exception(
    class_id: UUID,
    request: ClassRangeExceptionCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
    exceptions_service: ClassesExceptionsService = Depends(
        Provide[DependencyInjector.classes_exceptions_service]
    ),
) -> ClassRangeExceptionResponse:
    """Create a range exception."""
    user_payload = auth.get_current_user(credentials)
    existing = await _resolve_class_for_auth(
        crud_service, auth, class_id, user_payload, require_admin_or_owner=True
    )

    try:
        return await exceptions_service.create_range_exception(
            class_id, existing.gym_id, request
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create range exception: class_id=%s",
            class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create range exception",
        ) from None


@classes_router.get(
    "/{class_id}/exceptions/range",
    response_model=ClassRangeExceptionListResponse,
    summary="List a class's range exceptions in a window",
    responses={
        200: {"description": "Range exceptions listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def list_range_exceptions(
    class_id: UUID,
    start_date: date,
    end_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
    exceptions_service: ClassesExceptionsService = Depends(
        Provide[DependencyInjector.classes_exceptions_service]
    ),
) -> ClassRangeExceptionListResponse:
    """List range exceptions for a class within a window."""
    user_payload = auth.get_current_user(credentials)
    await _resolve_class_for_auth(crud_service, auth, class_id, user_payload)

    try:
        return await exceptions_service.list_range_exceptions(
            class_id, start_date, end_date
        )
    except Exception:
        logger.error(
            "Failed to list range exceptions: class_id=%s",
            class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list range exceptions",
        ) from None


@classes_router.get(
    "/{class_id}",
    response_model=GymClassResponse,
    summary="Get a single class by id",
    responses={
        200: {"description": "Class returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def get_class(
    class_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
) -> GymClassResponse:
    """Get a single class (gym-employee scoped)."""
    user_payload = auth.get_current_user(credentials)
    return await _resolve_class_for_auth(crud_service, auth, class_id, user_payload)


@classes_router.put(
    "/{class_id}",
    response_model=GymClassResponse,
    summary="Update a class",
    responses={
        200: {"description": "Class updated"},
        400: {"description": "Invalid update"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def update_class(
    class_id: UUID,
    request: GymClassUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
) -> GymClassResponse:
    """Update a class."""
    user_payload = auth.get_current_user(credentials)
    await _resolve_class_for_auth(
        crud_service, auth, class_id, user_payload, require_admin_or_owner=True
    )

    try:
        return await crud_service.update_class(class_id, request.data)
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
            "Failed to update class: class_id=%s", class_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update class",
        ) from None


@classes_router.delete(
    "/{class_id}",
    response_model=GymClassResponse,
    summary="Soft-delete a class",
    description="Sets ``is_deleted = TRUE`` and ``is_active = FALSE``.",
    responses={
        200: {"description": "Class soft-deleted"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Class not found"},
    },
)
@inject
async def soft_delete_class(
    class_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    crud_service: ClassesCrudService = Depends(
        Provide[DependencyInjector.classes_crud_service]
    ),
) -> GymClassResponse:
    """Soft-delete a class."""
    user_payload = auth.get_current_user(credentials)
    await _resolve_class_for_auth(
        crud_service, auth, class_id, user_payload, require_admin_or_owner=True
    )

    try:
        return await crud_service.soft_delete_class(class_id)
    except Exception:
        logger.error(
            "Failed to soft-delete class: class_id=%s", class_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to soft-delete class",
        ) from None


async def _resolve_class_for_auth(
    crud_service: ClassesCrudService,
    auth: Auth,
    class_id: UUID,
    user_payload: dict,
    *,
    require_admin_or_owner: bool = False,
) -> GymClassResponse:
    """Load a class (404 if absent) and gate the caller on its gym.

    Reads gate at gym-employee level; writes pass
    ``require_admin_or_owner=True`` to gate at admin-or-owner instead.
    """
    try:
        existing = await crud_service.get_class(class_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Class not found",
        ) from None
    if require_admin_or_owner:
        await auth.verify_gym_admin_or_owner(existing.gym_id, user_payload)
    else:
        await auth.verify_gym_employee(existing.gym_id, user_payload)
    return existing
