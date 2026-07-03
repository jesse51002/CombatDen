"""List a waiver's immutable version history (with per-version sign counts)."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import WaiverVersionResponse
from src.waivers.service.waivers_base import WaiversBase


class WaiversVersions(WaiversBase):
    """Read-only listing of a waiver's published versions."""

    async def list_versions(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> list[WaiverVersionResponse]:
        """Return every version of a waiver, newest first, each with the count
        of members who signed that exact version."""
        sql = load_sql(SQL_DIR / "waiver_versions_list.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [WaiverVersionResponse(**dict(row)) for row in rows]
