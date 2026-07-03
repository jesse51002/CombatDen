"""List + read waivers for a gym."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import WaiverResponse
from src.waivers.service.waivers_base import WaiversBase


class WaiversList(WaiversBase):
    """Read-only listing + single-read of waivers for a gym."""

    async def list_waivers(
        self,
        gym_id: UUID,
    ) -> list[WaiverResponse]:
        """Return all non-deleted waivers for the gym (no body), newest first.

        Each row carries the current version number and how many members have
        signed the current version.
        """
        sql = load_sql(SQL_DIR / "waivers_list.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [self._build_summary_response(dict(row)) for row in rows]

    async def get_waiver(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> WaiverResponse:
        """Return one waiver with its current version body embedded.

        Raises:
            ValueError: If the waiver is not found.
        """
        return await self._load_full_waiver(waiver_id, gym_id)
