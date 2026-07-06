"""Ranks domain facade.

Composes the rank concern services — ``RanksMembers`` (member-rank
changes + backfill), ``RanksGroups`` (full-ladder reorder + whole-group
rename / delete), and ``RanksPresets`` (seed-from-preset + preset reads) —
behind the single public API the router injects. The facade itself keeps
the small, self-contained concerns: single-rank CRUD and the
``is_rank_enabled`` toggle. Everything member / group / preset shaped is
pure delegation.

The two side-effecting rules that shape the domain still hold: creating a
rank (or seeding from a preset, or flipping the gym's rank toggle on)
backfills every rank-less member to the lowest rank via ``RanksMembers``,
and deleting a rank downgrades affected members first so the composite FK
never dangles.
"""

from uuid import UUID

from schema.gym_rank import GymType
from schema.immutable_columns import GYM_RANKS as GYM_RANKS_IMMUTABLE
from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankMemberResponse,
    RankPresetListResponse,
    RankPromoteMemberRequest,
    RankRenameGroupRequest,
    RankReorderRequest,
    RankResponse,
    RankSetMemberRequest,
    RankUpdateData,
)
from src.ranks.service.ranks_base import RanksBase
from src.ranks.service.ranks_groups import RanksGroups
from src.ranks.service.ranks_members import RanksMembers
from src.ranks.service.ranks_presets import RanksPresets
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class RanksService(RanksBase):
    """All rank operations for a gym (facade over the concerns)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        members: RanksMembers,
        groups: RanksGroups,
        presets: RanksPresets,
    ) -> None:
        super().__init__(db_pool)
        self._members = members
        self._groups = groups
        self._presets = presets

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
                "color": request.color,
            }
            row = (await session.execute(text(insert_sql), params)).mappings().fetchone()
            if not row:
                raise RuntimeError("INSERT did not return a row")

            if await self._members.is_rank_enabled(session, request.gym_id):
                await self._members.backfill_lowest_for_gym(
                    session,
                    request.gym_id,
                )

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
        async with self._db_pool.session() as session:
            items = await self._list_ranks_in_session(session, gym_id)
        return RankListResponse(items=items)

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

    # ---------- member rank changes (→ RanksMembers) ----------

    async def promote_member(
        self,
        request: RankPromoteMemberRequest,
    ) -> RankMemberResponse:
        """Advance a member one step up the gym's ordered ladder."""
        return await self._members.promote_member(request)

    async def set_member_rank(
        self,
        request: RankSetMemberRequest,
    ) -> RankMemberResponse:
        """Set a member to an explicit rank, or to no rank."""
        return await self._members.set_member_rank(request)

    # ---------- full-ladder reorder + whole-group ops (→ RanksGroups) ----------

    async def reorder_ranks(
        self,
        request: RankReorderRequest,
    ) -> RankListResponse:
        """Apply a full new ordering to a gym's ranks atomically."""
        return await self._groups.reorder_ranks(request)

    async def rename_group(
        self,
        request: RankRenameGroupRequest,
    ) -> RankListResponse:
        """Rename a main-rank group in one atomic UPDATE."""
        return await self._groups.rename_group(request)

    async def delete_group(
        self,
        gym_id: UUID,
        main_rank_num_order: int,
    ) -> None:
        """Downgrade affected members, then delete a whole main group."""
        return await self._groups.delete_group(gym_id, main_rank_num_order)

    # ---------- preset flows (→ RanksPresets) ----------

    async def from_preset(
        self,
        request: FromPresetRequest,
    ) -> RankListResponse:
        """Bulk-clone a preset ladder into a gym, then backfill."""
        return await self._presets.from_preset(request)

    async def list_presets(
        self,
        gym_type: GymType,
    ) -> RankPresetListResponse:
        """Flat preset list for a single gym_type."""
        return await self._presets.list_presets(gym_type)

    async def get_all_presets_grouped(self) -> AllPresetsGroupedResponse:
        """All preset ladders, keyed by gym_type, nested main → sub."""
        return await self._presets.get_all_presets_grouped()

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
                await self._members.backfill_lowest_for_gym(
                    session,
                    request.gym_id,
                )

            await session.commit()
            return RankEnabledResponse(**dict(row))
