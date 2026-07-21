"""API routes for the employees domain.

Live CRUD for a gym's staff roster (``gym_employees``). Staff management is
owner/admin only, so every endpoint guards ``verify_roles(..., OWNER_ADMIN)``.
Identity is the lowercase ``email`` column — a verified Supabase auth account
whose email matches a row is that person's login; creating an employee is a
plain INSERT with no auth-system interaction, and archiving is a soft-delete
that touches no auth row (access dies because every check filters
``archived_at IS NULL``).
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.employees.employees_exceptions import (
    DuplicateEmployeeError,
    EmployeeNotFoundError,
    OwnerRowProtectedError,
)
from src.employees.schema.employees_schema import (
    EmployeeCreateRequest,
    EmployeeListResponse,
    EmployeeResponse,
    EmployeeUpdateRequest,
)
from src.employees.service.employees_service import EmployeesService
from src.shared.auth import OWNER_ADMIN, Auth, security

logger = logging.getLogger(__name__)

employees_router = APIRouter(
    prefix="/api/v1/employees",
    tags=["employees"],
)


@employees_router.get(
    "/{gym_id}",
    response_model=EmployeeListResponse,
    status_code=status.HTTP_200_OK,
    summary="List a gym's employees",
    description=(
        "Lists all non-archived employees of the gym (every type), each with "
        "its derived invite status. Owner/admin only."
    ),
    responses={
        200: {"description": "Employees listed successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_employees(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    employees_service: EmployeesService = Depends(
        Provide[DependencyInjector.employees_service]
    ),
) -> EmployeeListResponse:
    """List a gym's employees.

    Raises:
        HTTPException: 401/403/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, OWNER_ADMIN)

    try:
        return await employees_service.list_employees(gym_id)
    except Exception:
        logger.error(
            "Failed to list employees for gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list employees",
        ) from None


@employees_router.post(
    "/{gym_id}",
    response_model=EmployeeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create an employee",
    description=(
        "Creates a gym staff member (owner/admin only). A plain INSERT — no "
        "auth-system interaction; a verified auth account whose email matches "
        "becomes the person's login. The type may not be 'owner'."
    ),
    responses={
        201: {"description": "Employee created successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        409: {"description": "An employee with this email already exists"},
    },
)
@inject
async def create_employee(
    gym_id: UUID,
    request: EmployeeCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    employees_service: EmployeesService = Depends(
        Provide[DependencyInjector.employees_service]
    ),
) -> EmployeeResponse:
    """Create an employee.

    Raises:
        HTTPException: 400/401/403/409/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, OWNER_ADMIN)

    try:
        return await employees_service.create_employee(gym_id, request)
    except DuplicateEmployeeError as exc:
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
            "Failed to create employee for gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create employee",
        ) from None


@employees_router.put(
    "/{gym_id}/{employee_id}",
    response_model=EmployeeResponse,
    status_code=status.HTTP_200_OK,
    summary="Update an employee",
    description=(
        "Updates a gym staff member (owner/admin only). The owner row may be "
        "edited only by the owner themselves, and the owner's role can never "
        "change; no employee may be set to 'owner'."
    ),
    responses={
        200: {"description": "Employee updated successfully"},
        400: {"description": "Invalid request data"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized / owner-row protected"},
        404: {"description": "Employee not found"},
        409: {"description": "Email already used at this gym"},
    },
)
@inject
async def update_employee(
    gym_id: UUID,
    employee_id: UUID,
    request: EmployeeUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    employees_service: EmployeesService = Depends(
        Provide[DependencyInjector.employees_service]
    ),
) -> EmployeeResponse:
    """Update an employee.

    Raises:
        HTTPException: 400/401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    # get_employee_id applies the SAME owner/admin gate as verify_roles and
    # additionally returns the id, so it is the whole authorization step —
    # needed for the owner-self-edit rule (an owner may edit only their own
    # row). Calling verify_roles first would just repeat the query.
    caller_employee_id = await auth.get_employee_id(
        gym_id, user_payload, OWNER_ADMIN
    )

    try:
        return await employees_service.update_employee(
            gym_id,
            employee_id,
            request.data,
            caller_employee_id,
        )
    except OwnerRowProtectedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        ) from None
    except EmployeeNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except DuplicateEmployeeError as exc:
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
            "Failed to update employee %s", employee_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update employee",
        ) from None


@employees_router.delete(
    "/{gym_id}/{employee_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Archive an employee",
    description=(
        "Soft-archives a gym staff member (owner/admin only). No auth-system "
        "row is touched — access dies because every check filters archived "
        "rows. The gym owner can never be archived."
    ),
    responses={
        204: {"description": "Employee archived successfully"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized / owner cannot be archived"},
        404: {"description": "Employee not found"},
    },
)
@inject
async def delete_employee(
    gym_id: UUID,
    employee_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    employees_service: EmployeesService = Depends(
        Provide[DependencyInjector.employees_service]
    ),
) -> None:
    """Archive an employee.

    Raises:
        HTTPException: 401/403/404/500 on respective errors.
    """
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(gym_id, user_payload, OWNER_ADMIN)

    try:
        await employees_service.archive_employee(gym_id, employee_id)
    except OwnerRowProtectedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(exc),
        ) from None
    except EmployeeNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to archive employee %s", employee_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to archive employee",
        ) from None
