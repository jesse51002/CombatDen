"""Create an employee — a plain INSERT with no auth-system interaction.

A verified Supabase ``auth.users`` account whose email matches the inserted
row is that person's login; nothing is provisioned here. A duplicate email
at the gym trips the ``unique_employee_email_gym`` partial unique index and
surfaces as a 409 to the caller.
"""

from __future__ import annotations

from uuid import UUID

from schema.email import EmailKind
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.emails.schema.emails_schema import (
    InviteOutcome,
    StaffOnboardingEmail,
)
from src.emails.service.emails_service import EmailsService
from src.employees import SQL_DIR
from src.employees.schema.employees_schema import (
    EmployeeCreateRequest,
    EmployeeCreateResult,
)
from src.employees.service.employees_base import EmployeesBase
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class EmployeesCreate(EmployeesBase):
    """Insert a gym staff member and return the created row."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        emails_service: EmailsService,
    ) -> None:
        super().__init__(db_pool)
        self._emails = emails_service

    async def create_employee(
        self,
        gym_id: UUID,
        request: EmployeeCreateRequest,
    ) -> EmployeeCreateResult:
        """Insert the employee and return it with its invite status.

        Email is already lowercased by the schema validator. Re-reads the
        row via ``_get_employee`` so ``invite_status`` reflects any
        pre-existing verified account for that email.

        Raises:
            DuplicateEmployeeError: If the email already exists at this gym.
            ValueError: On any other integrity failure (bad input).
        """
        sql = load_sql(SQL_DIR / "employees_insert.sql")
        params = {
            "gym_id": str(gym_id),
            "employee_type": request.employee_type.value,
            "first_name": request.first_name,
            "last_name": request.last_name,
            "phone": request.phone,
            "email": request.email,
            "employee_public_description": request.employee_public_description,
        }

        try:
            async with self._db_pool.session() as session:
                result = await session.execute(text(sql), params)
                employee_id = result.mappings().one()["employee_id"]
                await session.commit()
        except IntegrityError as exc:
            self._raise_for_integrity_error(exc)

        employee = await self._get_employee(gym_id, UUID(str(employee_id)))
        if not request.send_invite:
            return EmployeeCreateResult(
                employee=employee,
                invite=InviteOutcome.not_requested,
            )
        # Claimed only AFTER the row is committed, never before: an invite
        # about a person who does not exist is worse than a missing one. The
        # inverse risk — a crash between the two — leaves the roster row
        # badged `pending` with a Resend action beside it, which is exactly
        # the affordance that repairs it.
        email_id, outcome = await self._emails.request_send(
            StaffOnboardingEmail(
                kind=EmailKind.staff_onboarding,
                gym_id=gym_id,
                employee_id=employee.employee_id,
            )
        )
        return EmployeeCreateResult(
            employee=employee,
            invite=outcome,
            email_id=email_id,
        )
