"""Ranks domain facade.

Composes the rank concern services — ``RanksMembers`` (member-rank
changes + backfill), ``RanksGroups`` (full-ladder reorder),
``RanksPresets`` (seed-from-preset + preset reads), and ``RanksReads``
(the two paginated member-board reads) — behind the single public API
the router injects. The facade itself keeps the small, self-contained
concerns: single-rank CRUD and the ``is_rank_enabled`` toggle. Everything
member / reorder / preset / read shaped is pure delegation.

The two side-effecting rules that shape the domain still hold: creating a
rank (or seeding from a preset, or flipping the gym's rank toggle on)
backfills every rank-less member to the lowest leaf via ``RanksMembers``,
and deleting a rank downgrades affected members first so the composite FK
never dangles.
"""

import json
from uuid import UUID

from schema.gym_rank import RankPresetKind
from schema.immutable_columns import GYM_RANKS as GYM_RANKS_IMMUTABLE
from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    MembersInRankRequest,
    MembersInRankResponse,
    MembersReadyToPromoteRequest,
    MembersReadyToPromoteResponse,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankMemberResponse,
    RankPresetListResponse,
    RankPromoteMemberRequest,
    RankReorderRequest,
    RankResponse,
    RankSetMemberRequest,
    RankSubRankCountsResponse,
    RankUpdateData,
)
from src.ranks.service.ranks_base import RanksBase
from src.ranks.service.ranks_groups import RanksGroups
from src.ranks.service.ranks_members import RanksMembers
from src.ranks.service.ranks_presets import RanksPresets
from src.ranks.service.ranks_reads import RanksReads
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

# The one JSONB column on gym_ranks — bound as CAST(:col AS JSONB) with a
# json.dumps'd value; every other mutable column binds as a plain :col.
_JSONB_COLUMNS = frozenset({"sub_rank_image_overrides"})


class RanksService(RanksBase):
    """All rank operations for a gym (facade over the concerns)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        members: RanksMembers,
        groups: RanksGroups,
        presets: RanksPresets,
        reads: RanksReads,
    ) -> None:
        super().__init__(db_pool)
        self._members = members
        self._groups = groups
        self._presets = presets
        self._reads = reads

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
                "name": request.name,
                "image_url": request.image_url,
                "classes_to_next_major": request.classes_to_next_major,
                "sub_rank_count": request.sub_rank_count,
                "sub_rank_image_overrides": json.dumps(
                    request.sub_rank_image_overrides
                ),
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
        """Update mutable fields on a rank row.

        The SET clause is built with PER-COLUMN casts — the JSONB
        overrides map as ``CAST(:col AS JSONB)`` over a json.dumps'd
        value, every other column as a plain ``:col`` (never
        ``:col::type``). When ``sub_rank_count`` is in the payload,
        members on this rank are re-clamped in the SAME transaction, but
        the overrides map is never pruned (persist-only).
        """
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(
            GYM_RANKS_IMMUTABLE,
            set(update_fields.keys()),
        )

        set_parts: list[str] = []
        params: dict = {"rank_id": str(rank_id)}
        for col, value in update_fields.items():
            if col in _JSONB_COLUMNS:
                set_parts.append(f"{col} = CAST(:{col} AS JSONB)")
                params[col] = json.dumps(value)
            else:
                set_parts.append(f"{col} = :{col}")
                params[col] = value
        set_clause = ", ".join(set_parts)

        sql = load_sql(
            SQL_DIR / "update_rank.sql",
            {"set_clause": set_clause},
        )
        async with self._db_pool.session() as session:
            row = (await session.execute(text(sql), params)).mappings().fetchone()
            if not row:
                raise ValueError("Rank not found")

            if "sub_rank_count" in update_fields:
                clamp_sql = load_sql(SQL_DIR / "clamp_member_sub_index.sql")
                await session.execute(
                    text(clamp_sql),
                    {
                        "gym_id": str(row["gym_id"]),
                        "rank_id": str(rank_id),
                        "new_count": update_fields["sub_rank_count"],
                    },
                )

            await session.commit()
            return RankResponse(**dict(row))

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
        """List a gym's ladder + its sub_rank_type (ordered by main)."""
        async with self._db_pool.session() as session:
            items = await self._list_ranks_in_session(session, gym_id)
            sub_rank_type = await self._gym_sub_rank_type(session, gym_id)
        return RankListResponse(items=items, sub_rank_type=sub_rank_type)

    async def delete_rank(self, rank_id: UUID) -> None:
        """Downgrade affected members, then hard-delete the rank.

        The composite FK ``(current_rank_id, gym_id)`` on members
        means a naive DELETE would fail if any member is on this
        rank. Find the best replacement (lower first, else higher,
        else NULL), reassign members to its base leaf, then DELETE.
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
        """Advance a member one leaf up the gym's ordered ladder."""
        return await self._members.promote_member(request)

    async def set_member_rank(
        self,
        request: RankSetMemberRequest,
    ) -> RankMemberResponse:
        """Set a member to an explicit leaf, or to no rank."""
        return await self._members.set_member_rank(request)

    # ---------- full-ladder reorder (→ RanksGroups) ----------

    async def reorder_ranks(
        self,
        request: RankReorderRequest,
    ) -> RankListResponse:
        """Apply a full new ordering to a gym's ranks atomically."""
        return await self._groups.reorder_ranks(request)

    # ---------- preset flows (→ RanksPresets) ----------

    async def from_preset(
        self,
        request: FromPresetRequest,
    ) -> RankListResponse:
        """Bulk-clone a preset ladder into a gym, then backfill."""
        return await self._presets.from_preset(request)

    async def list_presets(
        self,
        preset_kind: RankPresetKind,
    ) -> RankPresetListResponse:
        """Flat preset list for a single preset kind."""
        return await self._presets.list_presets(preset_kind)

    async def get_all_presets_grouped(self) -> AllPresetsGroupedResponse:
        """All preset ladders, keyed by preset kind (flat main rows)."""
        return await self._presets.get_all_presets_grouped()

    # ---------- paginated member reads (→ RanksReads) ----------

    async def list_ready_to_promote(
        self,
        request: MembersReadyToPromoteRequest,
    ) -> MembersReadyToPromoteResponse:
        """Members closest to their next promotion, paginated."""
        return await self._reads.list_ready_to_promote(request)

    async def list_members_in_rank(
        self,
        request: MembersInRankRequest,
    ) -> MembersInRankResponse:
        """Members currently on one main rank, paginated."""
        return await self._reads.list_members_in_rank(request)

    async def count_members_by_sub_index(
        self,
        gym_id: UUID,
        rank_id: UUID,
    ) -> RankSubRankCountsResponse:
        """Member counts per sub-position for one main rank."""
        return await self._reads.count_members_by_sub_index(gym_id, rank_id)

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

        Only false→true triggers the backfill. The backfill helper has
        its own empty-ladder guard so a gym with no ranks is a no-op.
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
