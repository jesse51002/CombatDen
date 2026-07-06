"""Ranks preset concern: seed-from-preset + preset catalog reads.

Cloning a preset ladder into a gym also copies the preset kind's implied
sub-rank type onto the gym, then runs the same lowest-rank backfill as
the other rank-enabling flows, so this concern composes ``RanksMembers``
for that shared step (its backfill runs inside the seed's own
transaction).
"""

from schema.gym_rank import RankPresetKind
from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    RankListResponse,
    RankPresetListResponse,
    RankPresetResponse,
)
from src.ranks.service.ranks_base import RanksBase
from src.ranks.service.ranks_members import RanksMembers
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class RanksPresets(RanksBase):
    """Seed a gym's ladder from a preset + read the preset catalog."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        members: RanksMembers,
    ) -> None:
        super().__init__(db_pool)
        self._members = members

    async def from_preset(
        self,
        request: FromPresetRequest,
    ) -> RankListResponse:
        """Clone a preset ladder into a gym, set its type, reconcile, backfill.

        Runs four steps in one transaction: insert the preset's main
        rows (idempotent), copy the preset kind's implied sub-rank type
        onto the gym (every kind implies one now — ``'none'`` for plain
        belts / flat), reconcile EXISTING members' ``current_sub_index``
        to that style so the leaf invariant stays valid, then backfill
        rank-less members to the lowest leaf if ranks are enabled.
        """
        async with self._db_pool.session() as session:
            insert_sql = load_sql(SQL_DIR / "insert_ranks_from_preset.sql")
            await session.execute(
                text(insert_sql),
                {
                    "gym_id": str(request.gym_id),
                    "preset_kind": request.preset_kind.value,
                },
            )

            type_sql = load_sql(
                SQL_DIR / "set_gym_sub_rank_type_from_preset.sql"
            )
            await session.execute(
                text(type_sql),
                {
                    "gym_id": str(request.gym_id),
                    "preset_kind": request.preset_kind.value,
                },
            )

            # The preset just set the gym's style; reconcile existing
            # members' sub-index to it (rank-less members are handled by
            # the backfill below). Read the now-effective style once and
            # reuse it for the reconcile AND the response.
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            await self._members.reconcile_sub_index_in_session(
                session,
                request.gym_id,
                sub_rank_type,
            )

            if await self._members.is_rank_enabled(session, request.gym_id):
                await self._members.backfill_lowest_for_gym(
                    session,
                    request.gym_id,
                )

            items = await self._list_ranks_in_session(session, request.gym_id)
            await session.commit()

        return RankListResponse(items=items, sub_rank_type=sub_rank_type)

    async def list_presets(
        self,
        preset_kind: RankPresetKind,
    ) -> RankPresetListResponse:
        """Flat preset list for a single preset kind."""
        sql = load_sql(SQL_DIR / "list_presets.sql")
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), {"preset_kind": preset_kind.value}))
                .mappings()
                .all()
            )
        return RankPresetListResponse(
            items=[RankPresetResponse(**dict(row)) for row in rows],
        )

    async def get_all_presets_grouped(self) -> AllPresetsGroupedResponse:
        """All preset ladders, keyed by preset kind (flat main rows).

        Single SQL pass; rows arrive sorted by preset_kind then main
        order. Bucket them into one list per kind in one O(n) pass.
        """
        sql = load_sql(SQL_DIR / "list_all_presets.sql")
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()

        presets: dict[RankPresetKind, list[RankPresetResponse]] = {}
        for row in rows:
            preset_kind = RankPresetKind(row["preset_kind"])
            presets.setdefault(preset_kind, []).append(
                RankPresetResponse(**dict(row))
            )

        return AllPresetsGroupedResponse(presets=presets)
