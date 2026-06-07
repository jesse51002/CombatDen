"""Read-only waiver signature tracking.

Two views, both gym-scoped: a per-waiver roster (every member + whether they
signed it) and a per-member status list (every waiver + this member's status).
The signing-capture write path is Phase 2.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.sql_loader import load_sql
from src.waivers import SQL_DIR
from src.waivers.schema.waivers_schema import (
    MemberWaiverStatusRow,
    WaiverSignatoryRow,
)
from src.waivers.service.waivers.waivers_base import WaiversBase


class WaiversSignatures(WaiversBase):
    """Read-only signature tracking for waivers."""

    async def list_signatories(
        self,
        waiver_id: UUID,
        gym_id: UUID,
    ) -> list[WaiverSignatoryRow]:
        """Return every gym member and their latest sign status for a waiver."""
        sql = load_sql(SQL_DIR / "waiver_signatures_roster.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"waiver_id": str(waiver_id), "gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [WaiverSignatoryRow(**dict(row)) for row in rows]

    async def list_member_status(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> list[MemberWaiverStatusRow]:
        """Return every gym waiver and this member's latest sign status for it."""
        sql = load_sql(SQL_DIR / "waiver_signatures_by_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id), "gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [MemberWaiverStatusRow(**dict(row)) for row in rows]
