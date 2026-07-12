"""Update an employee — a dynamic partial UPDATE over the provided fields.

Only the fields the client actually sent (non-None) are written, guarded
against the immutable-column set. The owner row is protected: it can only be
edited by the owner themselves, and its ``employee_type`` can never change
(``owner`` as a target value is already blocked at the schema layer).
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.gym_employee import EmployeeType
from schema.immutable_columns import GYM_EMPLOYEES
from sqlalchemy import text

from src.employees import SQL_DIR
from src.employees.employees_exceptions import (
    EmployeeNotFoundError,
    OwnerRowProtectedError,
)
from src.employees.schema.employees_schema import (
    EmployeeResponse,
    EmployeeUpdateData,
)
from src.employees.service.employees_base import EmployeesBase
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_ENUM_COLUMN = "employee_type"


class EmployeesUpdate(EmployeesBase):
    """Apply a partial update to a gym staff member."""

    async def update_employee(
        self,
        gym_id: UUID,
        employee_id: UUID,
        data: EmployeeUpdateData,
        caller_employee_id: UUID,
    ) -> EmployeeResponse:
        """Update the mutable fields the client sent, then return the row.

        Args:
            gym_id: The gym owning the employee (authorization scope).
            employee_id: The employee to update.
            data: The mutable fields; ``None`` means "leave unchanged".
            caller_employee_id: The acting owner/admin's own employee id
                (for the owner-self-edit rule).

        Raises:
            EmployeeNotFoundError: If no live employee row matches.
            OwnerRowProtectedError: If the owner row is edited by anyone
                other than the owner, or its role change is attempted.
            ValueError: If a provided field is immutable.
        """
        changes = data.model_dump(exclude_none=True, mode="json")
        validate_mutable_columns(GYM_EMPLOYEES, set(changes.keys()))

        target = await self._get_employee(gym_id, employee_id)
        self._enforce_owner_rules(target, employee_id, data, caller_employee_id)

        if changes:
            await self._apply_update(gym_id, employee_id, changes)

        return await self._get_employee(gym_id, employee_id)

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _enforce_owner_rules(
        target: EmployeeResponse,
        employee_id: UUID,
        data: EmployeeUpdateData,
        caller_employee_id: UUID,
    ) -> None:
        """Guard edits to the owner row.

        The owner row may be edited ONLY by the owner themselves, and the
        owner's ``employee_type`` is immutable. A non-owner target is
        unrestricted here.
        """
        if target.employee_type is not EmployeeType.owner:
            return
        if caller_employee_id != employee_id or data.employee_type is not None:
            raise OwnerRowProtectedError(
                "The owner row can only be edited by the owner, and the "
                "owner's role cannot be changed."
            )

    async def _apply_update(
        self,
        gym_id: UUID,
        employee_id: UUID,
        changes: dict,
    ) -> None:
        """Build + run the dynamic SET clause over the provided fields.

        The enum column casts via ``CAST(:employee_type AS employee_type)``;
        every other field binds plainly. Column names come from the trusted
        schema field set, never client-controlled strings.

        Raises:
            EmployeeNotFoundError: If the row disappeared before the write.
        """
        set_parts: list[str] = []
        params: dict = {
            "employee_id": str(employee_id),
            "gym_id": str(gym_id),
        }
        for col, value in changes.items():
            if col == _ENUM_COLUMN:
                set_parts.append(
                    "employee_type = CAST(:employee_type AS employee_type)"
                )
            else:
                set_parts.append(f"{col} = :{col}")
            params[col] = value

        sql = load_sql(
            SQL_DIR / "employees_update.sql",
            {"set_clause": ", ".join(set_parts)},
        )
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            if not result.mappings().fetchone():
                raise EmployeeNotFoundError(
                    f"Employee {employee_id} not found"
                )
            await session.commit()
