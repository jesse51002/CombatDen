"""Employee CRUD operations (facade).

Live CRUD for a gym's staff roster (``gym_employees``). Employees are plain
gym config (no Stripe): identity is the lowercase ``email`` column, and a
verified Supabase ``auth.users`` account whose email matches is that
person's login. This facade constructs and one-line-delegates to the focused
sub-services for list/read, create, update, and archive.
"""

from __future__ import annotations

from uuid import UUID

from src.emails.service.emails_service import EmailsService
from src.employees.schema.employees_schema import (
    EmployeeCreateRequest,
    EmployeeCreateResult,
    EmployeeListResponse,
    EmployeeResponse,
    EmployeeUpdateData,
)
from src.employees.service.employees_archive import EmployeesArchive
from src.employees.service.employees_create import EmployeesCreate
from src.employees.service.employees_list import EmployeesList
from src.employees.service.employees_update import EmployeesUpdate
from src.shared.database import DirectDatabasePool


class EmployeesService:
    """Employee CRUD (facade).

    Delegates to focused sub-services for list/read, create, update, and
    archive.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        emails_service: EmailsService,
    ) -> None:
        self._list = EmployeesList(db_pool)
        self._create = EmployeesCreate(db_pool, emails_service)
        self._update = EmployeesUpdate(db_pool)
        self._archive = EmployeesArchive(db_pool)

    async def list_employees(
        self,
        gym_id: UUID,
    ) -> EmployeeListResponse:
        """List all non-archived employees of a gym (every type)."""
        employees = await self._list.list_employees(gym_id)
        return EmployeeListResponse(employees=employees)

    async def create_employee(
        self,
        gym_id: UUID,
        request: EmployeeCreateRequest,
    ) -> EmployeeCreateResult:
        """Create a staff member; claim their invite when asked to."""
        return await self._create.create_employee(gym_id, request)

    async def update_employee(
        self,
        gym_id: UUID,
        employee_id: UUID,
        data: EmployeeUpdateData,
        caller_employee_id: UUID,
    ) -> EmployeeResponse:
        """Update a gym staff member (owner-row rules enforced)."""
        return await self._update.update_employee(
            gym_id, employee_id, data, caller_employee_id
        )

    async def archive_employee(
        self,
        gym_id: UUID,
        employee_id: UUID,
    ) -> None:
        """Soft-archive a gym staff member (never the owner)."""
        await self._archive.archive_employee(gym_id, employee_id)
