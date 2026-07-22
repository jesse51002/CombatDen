"""List a gym's employees."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.employees import SQL_DIR
from src.employees.schema.employees_schema import EmployeeResponse
from src.employees.service.employees_base import EmployeesBase
from src.shared.sql_loader import load_sql


class EmployeesList(EmployeesBase):
    """Read-only listing of a gym's employees."""

    async def list_employees(
        self,
        gym_id: UUID,
    ) -> list[EmployeeResponse]:
        """Return all non-archived employees of the gym, oldest first.

        Every ``employee_type`` is included; each row carries its derived
        ``invite_status``.
        """
        sql = load_sql(SQL_DIR / "employees_list.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [self._row_to_response(dict(row)) for row in rows]
