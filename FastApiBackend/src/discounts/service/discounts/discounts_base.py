"""Shared dependencies and helpers for discount preset operations.

Presets are plain gym config now (coupon-free), so this base holds only the
DB pool — no Stripe service. Coupons are computed at sync-time and live on the
applied-discount snapshot, not the preset.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsBase:
    """Base class for discount preset sub-services.

    Holds the shared DB pool and reusable query methods used across
    create, update, delete, and list operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
    ) -> None:
        self._db_pool = db_pool

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_discount(self, discount_id: UUID) -> dict:
        """Fetch a non-deleted preset row.

        Raises:
            ValueError: If the preset is not found.
        """
        sql = load_sql(SQL_DIR / "discounts_get_by_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"discount_id": str(discount_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Discount {discount_id} not found")
        return dict(row)
