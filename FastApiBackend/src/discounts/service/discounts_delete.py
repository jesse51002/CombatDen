"""Archive (soft-delete) a regular discount preset.

Archive only: flips is_deleted = true. There is no Stripe coupon to delete
(coupons are computed at sync), no "strip from every membership" step, and no
payment-sync cascade. Existing applied-discount rows keep their frozen copy of
the discount, so a member's bill is untouched when a preset is archived.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.discounts import SQL_DIR
from src.discounts.service.discounts_base import DiscountsBase
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsDelete(DiscountsBase):
    """Archive a discount preset by soft-deleting it."""

    async def delete_discount(
        self,
        discount_id: UUID,
    ) -> None:
        """Archive a preset (is_deleted = true).

        Args:
            discount_id: The preset to archive.

        Raises:
            ValueError: If the preset is not found.
        """
        soft_delete_sql = load_sql(SQL_DIR / "discounts_soft_delete.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(soft_delete_sql),
                {"discount_id": str(discount_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Discount {discount_id} not found")
            await session.commit()
