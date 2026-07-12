"""Create an employee — a plain INSERT with no auth-system interaction.

A verified Supabase ``auth.users`` account whose email matches the inserted
row is that person's login; nothing is provisioned here. A duplicate email
at the gym trips the ``unique_employee_email_gym`` partial unique index and
surfaces as a 409 to the caller.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.employees import SQL_DIR
from src.employees.employees_exceptions import DuplicateEmployeeError
from src.employees.schema.employees_schema import (
    EmployeeCreateRequest,
    EmployeeResponse,
)
from src.employees.service.employees_base import EmployeesBase
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

# The partial unique index on (gym_id, lower(email)); its name appears in the
# Postgres unique-violation message, distinguishing a duplicate email from any
# other integrity failure.
_EMAIL_UNIQUE_CONSTRAINT = "unique_employee_email_gym"


class EmployeesCreate(EmployeesBase):
    """Insert a gym staff member and return the created row."""

    async def create_employee(
        self,
        gym_id: UUID,
        request: EmployeeCreateRequest,
    ) -> EmployeeResponse:
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
            if _EMAIL_UNIQUE_CONSTRAINT in str(exc.orig):
                raise DuplicateEmployeeError(
                    "An employee with this email already exists at this gym."
                ) from exc
            raise ValueError("Invalid employee data") from exc

        return await self._get_employee(gym_id, UUID(str(employee_id)))
