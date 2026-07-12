"""Archive (soft-delete) an employee.

Sets ``archived_at = now()``. The row is never hard-deleted (instructor +
waiver-operator FKs reference it), and access dies automatically because
every auth + read query filters ``archived_at IS NULL`` — no auth-system
row is ever touched here. The gym owner can never be archived.
"""

from __future__ import annotations

import logging
from uuid import UUID

from schema.gym_employee import EmployeeType
from sqlalchemy import text

from src.employees import SQL_DIR
from src.employees.employees_exceptions import (
    EmployeeNotFoundError,
    OwnerRowProtectedError,
)
from src.employees.service.employees_base import EmployeesBase
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class EmployeesArchive(EmployeesBase):
    """Soft-archive a gym staff member."""

    async def archive_employee(
        self,
        gym_id: UUID,
        employee_id: UUID,
    ) -> None:
        """Archive a live, non-owner employee.

        Args:
            gym_id: The gym owning the employee (authorization scope).
            employee_id: The employee to archive.

        Raises:
            OwnerRowProtectedError: If the target is the gym owner.
            EmployeeNotFoundError: If no live employee row matches.
        """
        sql = load_sql(SQL_DIR / "employees_archive.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"employee_id": str(employee_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()
            await session.commit()

        if row is not None:
            return

        # The archive matched nothing: distinguish the owner (protected) from
        # a missing / already-archived row. Loading the live row raises
        # EmployeeNotFoundError when it is gone (already archived or absent).
        target = await self._get_employee(gym_id, employee_id)
        if target.employee_type is EmployeeType.owner:
            raise OwnerRowProtectedError("The gym owner cannot be archived.")
        # A live non-owner row the archive somehow missed (a race) — treat as
        # not found rather than silently succeeding.
        raise EmployeeNotFoundError(f"Employee {employee_id} not found")
