"""List preset discounts for a gym."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import DiscountResponse
from src.discounts.service.discounts.discounts_base import DiscountsBase
from src.shared.sql_loader import load_sql


class DiscountsList(DiscountsBase):
    """Read-only listing of preset discounts for a gym."""

    async def list_discounts(
        self,
        gym_id: UUID,
    ) -> list[DiscountResponse]:
        """Return all non-deleted preset discounts for the gym, newest first."""
        sql = load_sql(SQL_DIR / "discounts_list.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [DiscountResponse(**dict(row)) for row in rows]
