"""Archive (soft-delete) a waiver catalog entry.

Flips is_deleted = true. The waiver's versions and any signatures are retained
(legal record); only the catalog entry is hidden from listings.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.service.waivers_base import WaiversBase

logger = logging.getLogger(__name__)


class WaiversDelete(WaiversBase):
    """Archive a waiver by soft-deleting its catalog entry."""

    async def delete_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Archive a waiver (is_deleted = true).

        Args:
            waiver_id: The waiver to archive.
            gym_id: The gym owning the waiver (authorization scope).

        Raises:
            ValueError: If the waiver is not found.
        """
        sql = load_sql(SQL_DIR / "waivers_soft_delete.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            if not result.mappings().fetchone():
                raise ValueError(f"Waiver {waiver_id} not found")
            await session.commit()
