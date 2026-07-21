"""Shared dependencies and helpers for employee operations.

Employees are plain gym config (no Stripe), so this base holds only the DB
pool plus the shared single-row fetch + the row → response mapper (which
derives ``invite_status`` from the auth-account join) used across list,
read, create, update, and archive.
"""

from __future__ import annotations

from typing import Any, NoReturn
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.employees import SQL_DIR
from src.employees.employees_exceptions import (
    DuplicateEmployeeError,
    EmployeeNotFoundError,
)
from src.employees.schema.employees_schema import (
    EmployeeResponse,
    InviteStatus,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

# The partial unique index on (gym_id, lower(email)); its name appears in the
# Postgres unique-violation message, distinguishing a duplicate email from any
# other integrity failure. Shared so create and update map it identically.
_EMAIL_UNIQUE_CONSTRAINT = "unique_employee_email_gym"


class EmployeesBase:
    """Base class for employee sub-services.

    Holds the shared DB pool and the reusable single-row fetch + mapper
    used across list, read, create, update, and archive operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    # ── Shared helpers ─────────────────────────────────────────

    @staticmethod
    def _raise_for_integrity_error(exc: IntegrityError) -> NoReturn:
        """Translate a write's integrity failure into a domain error.

        A duplicate email at the gym is a 409; anything else is bad input
        (400) rather than an uncaught 500. Both writers use this so create
        and update answer a duplicate email identically.

        Raises:
            DuplicateEmployeeError: On the email unique-index violation.
            ValueError: On any other integrity failure.
        """
        if _EMAIL_UNIQUE_CONSTRAINT in str(exc.orig):
            raise DuplicateEmployeeError(
                "An employee with this email already exists at this gym."
            ) from exc
        raise ValueError("Invalid employee data") from exc

    @staticmethod
    def _row_to_response(row: dict[str, Any]) -> EmployeeResponse:
        """Map a ``gym_employees`` read row to a response.

        Derives ``invite_status`` from the row: no email → ``none``; else
        the ``has_verified_account`` flag (a scalar ``EXISTS`` over
        ``auth.users``) → ``active`` when a verified account exists, else
        ``pending``.
        """
        email = row["email"]
        if email is None:
            invite_status = InviteStatus.none
        elif row["has_verified_account"]:
            invite_status = InviteStatus.active
        else:
            invite_status = InviteStatus.pending

        return EmployeeResponse(
            employee_id=row["employee_id"],
            gym_id=row["gym_id"],
            employee_type=row["employee_type"],
            first_name=row["first_name"],
            last_name=row["last_name"],
            phone=row["phone"],
            email=email,
            employee_pic_url=row["employee_pic_url"],
            employee_public_description=row["employee_public_description"],
            created_at=row["created_at"],
            invite_status=invite_status,
        )

    async def _get_employee(
        self,
        gym_id: UUID,
        employee_id: UUID,
    ) -> EmployeeResponse:
        """Fetch a single non-archived employee of a gym.

        Raises:
            EmployeeNotFoundError: If no live employee row matches.
        """
        sql = load_sql(SQL_DIR / "employees_get.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id), "employee_id": str(employee_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise EmployeeNotFoundError(f"Employee {employee_id} not found")
        return self._row_to_response(dict(row))
