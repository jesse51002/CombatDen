"""Ranks domain service: gym_ranks CRUD + presets + enabled toggle.

The service owns all the side-effecting flows the product rules
require — backfilling rank-less members to the lowest rank when a
gym's rank ladder becomes usable, and downgrading-then-deleting a
rank so the composite FK on members never goes dangling.
"""

import logging
from uuid import UUID

from schema.gym_rank import GymType
from schema.immutable_columns import GYM_RANKS as GYM_RANKS_IMMUTABLE
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    MainRankPresetGroup,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankPresetListResponse,
    RankPresetResponse,
    RankResponse,
    RankUpdateData,
    SubRankPreset,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class RanksService:
    """All rank operations for a gym."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    # ---------- single-rank CRUD ----------

    async def create_rank(
        self,
        request: RankCreateRequest,
    ) -> RankResponse:
        """Insert a rank and backfill rank-less members if enabled."""
        async with self._db_pool.session() as session:
            insert_sql = load_sql(SQL_DIR / "insert_rank.sql")
            params = {
                "gym_id": str(request.gym_id),
                "main_rank_num_order": request.main_rank_num_order,
                "sub_rank_num_order": request.sub_rank_num_order,
                "main_name": request.main_name,
                "sub_name": request.sub_name,
                "classes_till_rankup": request.classes_till_rankup,
                "image_url": request.image_url,
                "color": request.color,
            }
            row = (await session.execute(text(insert_sql), params)).mappings().fetchone()
            if not row:
                raise RuntimeError("INSERT did not return a row")

            if await self._is_rank_enabled(session, request.gym_id):
                await self._backfill_lowest_for_gym(session, request.gym_id)

            await session.commit()
            return RankResponse(**dict(row))

    async def update_rank(
        self,
        rank_id: UUID,
        data: RankUpdateData,
    ) -> RankResponse:
        """Update mutable fields on a rank row."""
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(
            GYM_RANKS_IMMUTABLE,
            set(update_fields.keys()),
        )

        set_clause = ", ".join(f"{col} = :{col}" for col in update_fields)
        sql = load_sql(
            SQL_DIR / "update_rank.sql",
            {"set_clause": set_clause},
        )
        params = {**update_fields, "rank_id": str(rank_id)}
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise ValueError("Rank not found")
        return RankResponse(**row)

    async def get_rank(self, rank_id: UUID) -> RankResponse:
        """Read a single rank row."""
        sql = load_sql(SQL_DIR / "get_rank.sql")
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), {"rank_id": str(rank_id)})).mappings().fetchone()
            )
        if not row:
            raise ValueError("Rank not found")
        return RankResponse(**dict(row))

    async def list_ranks(self, gym_id: UUID) -> RankListResponse:
        """List all ranks for a gym, ordered by main then sub."""
        sql = load_sql(SQL_DIR / "list_ranks.sql")
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql), {"gym_id": str(gym_id)})).mappings().all()
        return RankListResponse(
            items=[RankResponse(**dict(row)) for row in rows],
        )

    async def delete_rank(self, rank_id: UUID) -> None:
        """Downgrade affected members, then hard-delete the rank.

        The composite FK ``(current_rank_id, gym_id)`` on members
        means a naive DELETE would fail if any member is on this
        rank. Find the best replacement (lower first, else higher,
        else NULL), reassign members, then DELETE.
        """
        async with self._db_pool.session() as session:
            neighbor_sql = load_sql(SQL_DIR / "get_neighbor_ranks.sql")
            neighbor = (
                (
                    await session.execute(
                        text(neighbor_sql),
                        {"rank_id": str(rank_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
            if not neighbor or neighbor.get("gym_id") is None:
                raise ValueError("Rank not found")

            gym_id = neighbor["gym_id"]
            replacement = neighbor.get("lower_rank_id") or neighbor.get("higher_rank_id")

            reassign_sql = load_sql(SQL_DIR / "reassign_members_rank.sql")
            await session.execute(
                text(reassign_sql),
                {
                    "old_rank_id": str(rank_id),
                    "new_rank_id": str(replacement) if replacement else None,
                    "gym_id": str(gym_id),
                },
            )

            delete_sql = load_sql(SQL_DIR / "delete_rank.sql")
            await session.execute(
                text(delete_sql),
                {"rank_id": str(rank_id)},
            )
            await session.commit()

    # ---------- preset flows ----------

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

            if await self._is_rank_enabled(session, request.gym_id):
                await self._backfill_lowest_for_gym(session, request.gym_id)

            list_sql = load_sql(SQL_DIR / "list_ranks.sql")
            rows = (
                (
                    await session.execute(
                        text(list_sql),
                        {"gym_id": str(request.gym_id)},
                    )
                )
                .mappings()
                .all()
            )
            await session.commit()

        return RankListResponse(
            items=[RankResponse(**dict(row)) for row in rows],
        )

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

    # ---------- gyms.is_rank_enabled toggle ----------

    async def get_rank_enabled(self, gym_id: UUID) -> RankEnabledResponse:
        """Read the gym's current rank-enabled state."""
        sql = load_sql(SQL_DIR / "get_gym_rank_enabled.sql")
        async with self._db_pool.session() as session:
            row = (await session.execute(text(sql), {"gym_id": str(gym_id)})).mappings().fetchone()
        if not row:
            raise ValueError("Gym not found")
        return RankEnabledResponse(**dict(row))

    async def set_rank_enabled(
        self,
        request: RankEnabledRequest,
    ) -> RankEnabledResponse:
        """Toggle ``gyms.is_rank_enabled`` and run backfill on enable.

        Only false→true triggers the backfill. The backfill SQL has
        its own ``EXISTS`` guard so an empty-ladder gym is a no-op.
        """
        async with self._db_pool.session() as session:
            current_sql = load_sql(SQL_DIR / "get_gym_rank_enabled.sql")
            current_row = (
                (
                    await session.execute(
                        text(current_sql),
                        {"gym_id": str(request.gym_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
            if not current_row:
                raise ValueError("Gym not found")
            previously_enabled = bool(current_row["is_rank_enabled"])

            update_sql = load_sql(SQL_DIR / "update_gym_rank_enabled.sql")
            row = (
                (
                    await session.execute(
                        text(update_sql),
                        {
                            "gym_id": str(request.gym_id),
                            "is_rank_enabled": request.is_rank_enabled,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            if not row:
                raise ValueError("Gym not found")

            if request.is_rank_enabled and not previously_enabled:
                await self._backfill_lowest_for_gym(session, request.gym_id)

            await session.commit()
            return RankEnabledResponse(**dict(row))

    # ---------- private helpers ----------

    async def _is_rank_enabled(
        self,
        session: AsyncSession,
        gym_id: UUID,
    ) -> bool:
        """In-session check of ``gyms.is_rank_enabled``."""
        sql = load_sql(SQL_DIR / "get_gym_rank_enabled.sql")
        row = (await session.execute(text(sql), {"gym_id": str(gym_id)})).mappings().fetchone()
        if not row:
            raise ValueError("Gym not found")
        return bool(row["is_rank_enabled"])

    async def _backfill_lowest_for_gym(
        self,
        session: AsyncSession,
        gym_id: UUID,
    ) -> None:
        """Assign the lowest rank to every rank-less member of the gym.

        No-op if no ranks exist (the SQL's ``EXISTS`` guard handles
        the empty-ladder case).
        """
        sql = load_sql(SQL_DIR / "backfill_lowest_rank.sql")
        await session.execute(text(sql), {"gym_id": str(gym_id)})
