"""Ranks domain service: gym_ranks CRUD + presets + enabled toggle.

The service owns all the side-effecting flows the product rules
require — backfilling rank-less members to the lowest rank when a
gym's rank ladder becomes usable, and downgrading-then-deleting a
rank so the composite FK on members never goes dangling.
"""

import json
import logging
from uuid import UUID

from schema.gym_rank import GymType
from schema.immutable_columns import GYM_RANKS as GYM_RANKS_IMMUTABLE
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    RANK_CHANGED_ACTIVITY_TYPE,
    AllPresetsGroupedResponse,
    FromPresetRequest,
    MainRankPresetGroup,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankMemberResponse,
    RankPresetListResponse,
    RankPresetResponse,
    RankPromoteMemberRequest,
    RankRenameGroupRequest,
    RankReorderRequest,
    RankResponse,
    RankSetMemberRequest,
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

    # ---------- member rank changes ----------

    async def promote_member(
        self,
        request: RankPromoteMemberRequest,
    ) -> RankMemberResponse:
        """Advance a member one step up the gym's ordered ladder.

        A rank-less member is assigned the lowest rank (consistent
        with the enable-backfill). Promoting a member already at the
        top rank raises ``ValueError("highest rank")``. The rank
        update and the audit activity share one transaction.
        """
        async with self._db_pool.session() as session:
            old_rank_id, _ = await self._read_member_rank(
                session,
                request.member_id,
                request.gym_id,
            )

            ladder = await self._list_ranks_in_session(session, request.gym_id)
            if not ladder:
                raise ValueError("Gym has no ranks configured")

            new_rank = self._next_rank(ladder, old_rank_id)

            await self._apply_member_rank(
                session,
                member_id=request.member_id,
                gym_id=request.gym_id,
                old_rank_id=old_rank_id,
                new_rank_id=new_rank.rank_id,
            )
            await session.commit()

        return RankMemberResponse(member_id=request.member_id, new_rank=new_rank)

    async def set_member_rank(
        self,
        request: RankSetMemberRequest,
    ) -> RankMemberResponse:
        """Set a member to an explicit rank, or to no rank.

        Used for corrections, demotions, and assigning a rank-less
        member. A ``rank_id`` of ``None`` unassigns the member. The
        target rank must belong to the member's gym. The rank update
        and the audit activity share one transaction.
        """
        async with self._db_pool.session() as session:
            old_rank_id, _ = await self._read_member_rank(
                session,
                request.member_id,
                request.gym_id,
            )

            new_rank: RankResponse | None = None
            if request.rank_id is not None:
                new_rank = await self._read_rank_in_gym(
                    session,
                    request.rank_id,
                    request.gym_id,
                )

            await self._apply_member_rank(
                session,
                member_id=request.member_id,
                gym_id=request.gym_id,
                old_rank_id=old_rank_id,
                new_rank_id=request.rank_id,
            )
            await session.commit()

        return RankMemberResponse(member_id=request.member_id, new_rank=new_rank)

    async def reorder_ranks(
        self,
        request: RankReorderRequest,
    ) -> RankListResponse:
        """Apply a full new ordering to a gym's ranks atomically.

        The payload must cover the gym's ENTIRE ladder — every rank
        exactly once, target positions unique — validated up front so
        a bad payload is a clean ``ValueError`` (400) instead of a
        silent partial apply or a unique-constraint 500. Then a
        two-phase update in one transaction: shift every rank's main
        order into the +100000 space, then assign final orders. This
        keeps the non-deferrable unique-order constraint satisfied at
        every per-row check. Returns the reordered list.
        """
        ranks_json = json.dumps(
            [
                {
                    "rank_id": str(item.rank_id),
                    "main_rank_num_order": item.main_rank_num_order,
                    "sub_rank_num_order": item.sub_rank_num_order,
                }
                for item in request.ranks
            ]
        )
        params = {"gym_id": str(request.gym_id), "ranks": ranks_json}

        async with self._db_pool.session() as session:
            ladder = await self._list_ranks_in_session(session, request.gym_id)
            self._validate_reorder_payload(ladder, request)

            shift_sql = load_sql(SQL_DIR / "reorder_ranks_shift.sql")
            await session.execute(text(shift_sql), params)

            finalize_sql = load_sql(SQL_DIR / "reorder_ranks_finalize.sql")
            await session.execute(text(finalize_sql), params)

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

    @staticmethod
    def _validate_reorder_payload(
        ladder: list[RankResponse],
        request: RankReorderRequest,
    ) -> None:
        """Reject payloads that don't map the whole ladder cleanly."""
        payload_ids = [str(item.rank_id) for item in request.ranks]
        if len(set(payload_ids)) != len(payload_ids):
            raise ValueError("Duplicate rank_id in reorder payload")

        ladder_ids = {str(rank.rank_id) for rank in ladder}
        if set(payload_ids) - ladder_ids:
            raise ValueError(
                "Reorder payload contains ranks not in this gym's ladder"
            )
        if ladder_ids - set(payload_ids):
            raise ValueError(
                "Reorder payload must cover the gym's entire ladder"
            )

        positions = {
            (item.main_rank_num_order, item.sub_rank_num_order)
            for item in request.ranks
        }
        if len(positions) != len(request.ranks):
            raise ValueError("Duplicate target position in reorder payload")

    # ---------- whole-group operations ----------

    async def rename_group(
        self,
        request: RankRenameGroupRequest,
    ) -> RankListResponse:
        """Rename a main-rank group in one atomic UPDATE.

        ``main_name`` is denormalized onto every sub-rank row, so the
        rename spans all rows sharing the group's order — one
        statement, never a per-row fan-out.
        """
        async with self._db_pool.session() as session:
            sql = load_sql(SQL_DIR / "rename_rank_group.sql")
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(request.gym_id),
                            "main_rank_num_order": request.main_rank_num_order,
                            "new_main_name": request.new_main_name,
                        },
                    )
                )
                .mappings()
                .all()
            )
            if not rows:
                raise ValueError("Rank group not found")

            ladder = await self._list_ranks_in_session(session, request.gym_id)
            await session.commit()
        return RankListResponse(items=ladder)

    async def delete_group(
        self,
        gym_id: UUID,
        main_rank_num_order: int,
    ) -> None:
        """Downgrade affected members, then delete a whole main group.

        Group-level twin of ``delete_rank``: the replacement for
        members on any of the group's sub-ranks is the nearest lower
        group's highest sub-rank, else the nearest higher group's
        lowest, else NULL. Reassign, then delete every row of the
        group, in one transaction. Deliberately activity-silent — a
        rank deletion is not a promotion, so members' progress
        anchors are left untouched.
        """
        async with self._db_pool.session() as session:
            neighbor_sql = load_sql(SQL_DIR / "get_group_neighbor_ranks.sql")
            neighbor = (
                (
                    await session.execute(
                        text(neighbor_sql),
                        {
                            "gym_id": str(gym_id),
                            "main_rank_num_order": main_rank_num_order,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
            if not neighbor or neighbor.get("gym_id") is None:
                raise ValueError("Rank group not found")

            replacement = neighbor.get("lower_rank_id") or neighbor.get(
                "higher_rank_id"
            )

            reassign_sql = load_sql(SQL_DIR / "reassign_members_group.sql")
            await session.execute(
                text(reassign_sql),
                {
                    "gym_id": str(gym_id),
                    "main_rank_num_order": main_rank_num_order,
                    "new_rank_id": str(replacement) if replacement else None,
                },
            )

            delete_sql = load_sql(SQL_DIR / "delete_rank_group.sql")
            await session.execute(
                text(delete_sql),
                {
                    "gym_id": str(gym_id),
                    "main_rank_num_order": main_rank_num_order,
                },
            )
            await session.commit()

    # ---------- member-rank helpers ----------

    async def _read_member_rank(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
    ) -> tuple[UUID | None, UUID]:
        """Read a member's current rank id, asserting gym ownership."""
        sql = load_sql(SQL_DIR / "get_member_current_rank.sql")
        row = (
            (await session.execute(text(sql), {"member_id": str(member_id)}))
            .mappings()
            .fetchone()
        )
        if not row:
            raise ValueError("Member not found")
        if str(row["gym_id"]) != str(gym_id):
            raise ValueError("Member not found in this gym")
        return row["current_rank_id"], row["gym_id"]

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

    async def _read_rank_in_gym(
        self,
        session: AsyncSession,
        rank_id: UUID,
        gym_id: UUID,
    ) -> RankResponse:
        """Read one rank, asserting it belongs to the given gym."""
        sql = load_sql(SQL_DIR / "get_rank.sql")
        row = (
            (await session.execute(text(sql), {"rank_id": str(rank_id)}))
            .mappings()
            .fetchone()
        )
        if not row or str(row["gym_id"]) != str(gym_id):
            raise ValueError("Rank not found")
        return RankResponse(**dict(row))

    @staticmethod
    def _next_rank(
        ladder: list[RankResponse],
        current_rank_id: UUID | None,
    ) -> RankResponse:
        """The next rank up the ladder, or raise if already at top."""
        if current_rank_id is None:
            return ladder[0]
        index = next(
            (
                i
                for i, rank in enumerate(ladder)
                if str(rank.rank_id) == str(current_rank_id)
            ),
            None,
        )
        # A current rank that isn't in the ladder (e.g. just deleted)
        # falls back to the lowest rank rather than failing.
        if index is None:
            return ladder[0]
        if index >= len(ladder) - 1:
            raise ValueError("Member is already at the highest rank")
        return ladder[index + 1]

    async def _apply_member_rank(
        self,
        session: AsyncSession,
        *,
        member_id: UUID,
        gym_id: UUID,
        old_rank_id: UUID | None,
        new_rank_id: UUID | None,
    ) -> None:
        """Set a member's rank and log the change, in one session.

        The audit activity is written only when the rank actually
        changes, so a no-op set leaves no row.
        """
        set_sql = load_sql(SQL_DIR / "set_member_rank.sql")
        updated = (
            (
                await session.execute(
                    text(set_sql),
                    {
                        "new_rank_id": str(new_rank_id) if new_rank_id else None,
                        "member_id": str(member_id),
                        "gym_id": str(gym_id),
                    },
                )
            )
            .mappings()
            .fetchone()
        )
        if not updated:
            raise ValueError("Member not found")

        if str(old_rank_id) == str(new_rank_id):
            return

        activity_sql = load_sql(SQL_DIR / "insert_rank_activity.sql")
        await session.execute(
            text(activity_sql),
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "old_rank_id": str(old_rank_id) if old_rank_id else None,
                "new_rank_id": str(new_rank_id) if new_rank_id else None,
                "activity_type": RANK_CHANGED_ACTIVITY_TYPE,
            },
        )

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

        Writes one ``rank_changed`` activity per backfilled member in
        the same statement, so progress counts from the backfill
        moment (not the member's join date). No-op if no ranks exist
        (the SQL's empty ``lowest`` CTE handles the empty-ladder case).
        """
        sql = load_sql(SQL_DIR / "backfill_lowest_rank.sql")
        await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "activity_type": RANK_CHANGED_ACTIVITY_TYPE,
            },
        )
