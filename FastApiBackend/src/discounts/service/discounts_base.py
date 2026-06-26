"""Shared base for discount preset sub-services."""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsBase:
    """Base class for discount preset sub-services."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_discount(self, discount_id: UUID, gym_id: UUID) -> dict:
        """Fetch a non-deleted preset row scoped to its owning gym."""
        sql = load_sql(SQL_DIR / "discounts_get_by_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"discount_id": str(discount_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Discount {discount_id} not found")
        return dict(row)
