"""Shared base for the ranks concern services.

Holds the direct DB pool and the single read every concern needs — the
gym's ordered ladder, read inside an already-open session so it shares
the caller's transaction.
"""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import RankResponse
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class RanksBase:
    """Common state + shared reads for every ranks service."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def _list_ranks_in_session(
        self,
        session: AsyncSession,
        gym_id: UUID,
    ) -> list[RankResponse]:
        """Ordered ladder for a gym, read inside an open session."""
        sql = load_sql(SQL_DIR / "list_ranks.sql")
        rows = (
            (await session.execute(text(sql), {"gym_id": str(gym_id)}))
            .mappings()
            .all()
        )
        return [RankResponse(**dict(row)) for row in rows]
