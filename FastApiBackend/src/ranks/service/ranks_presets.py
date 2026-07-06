"""Ranks preset concern: seed-from-preset + preset catalog reads.

Cloning a preset ladder into a gym runs the same lowest-rank backfill as
the other rank-enabling flows, so this concern composes ``RanksMembers``
for that shared step (its backfill runs inside the seed's own
transaction).
"""

from schema.gym_rank import GymType
from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    MainRankPresetGroup,
    RankListResponse,
    RankPresetListResponse,
    RankPresetResponse,
    SubRankPreset,
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
        """Bulk-clone a preset ladder into a gym, then backfill."""
        async with self._db_pool.session() as session:
            insert_sql = load_sql(SQL_DIR / "insert_ranks_from_preset.sql")
            await session.execute(
                text(insert_sql),
                {
                    "gym_id": str(request.gym_id),
                    "gym_type": request.gym_type.value,
                },
            )

            if await self._members.is_rank_enabled(session, request.gym_id):
                await self._members.backfill_lowest_for_gym(
                    session,
                    request.gym_id,
                )

            items = await self._list_ranks_in_session(session, request.gym_id)
            await session.commit()

        return RankListResponse(items=items)

    async def list_presets(
        self,
        gym_type: GymType,
    ) -> RankPresetListResponse:
        """Flat preset list for a single gym_type."""
        sql = load_sql(SQL_DIR / "list_presets.sql")
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), {"gym_type": gym_type.value})).mappings().all()
            )
        return RankPresetListResponse(
            items=[RankPresetResponse(**dict(row)) for row in rows],
        )

    async def get_all_presets_grouped(self) -> AllPresetsGroupedResponse:
        """All preset ladders, keyed by gym_type, nested main → sub.

        Single SQL pass; rows arrive sorted by gym_type, main, sub.
        Build the nested structure in one O(n) iteration, opening a
        new ``MainRankPresetGroup`` whenever ``(gym_type, main)``
        changes.
        """
        sql = load_sql(SQL_DIR / "list_all_presets.sql")
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()

        presets: dict[GymType, list[MainRankPresetGroup]] = {}
        current_key: tuple[GymType, int] | None = None
        current_group: MainRankPresetGroup | None = None

        for row in rows:
            gym_type = GymType(row["gym_type"])
            main_order = row["main_rank_num_order"]
            key = (gym_type, main_order)

            if key != current_key:
                current_group = MainRankPresetGroup(
                    main_rank_num_order=main_order,
                    main_name=row["main_name"],
                    sub_ranks=[],
                )
                presets.setdefault(gym_type, []).append(current_group)
                current_key = key

            assert current_group is not None  # noqa: S101 — invariant
            current_group.sub_ranks.append(
                SubRankPreset(
                    preset_id=row["preset_id"],
                    sub_rank_num_order=row["sub_rank_num_order"],
                    sub_name=row["sub_name"],
                    classes_till_rankup=row["classes_till_rankup"],
                    image_url=row["image_url"],
                    color=row["color"],
                )
            )

        return AllPresetsGroupedResponse(presets=presets)
