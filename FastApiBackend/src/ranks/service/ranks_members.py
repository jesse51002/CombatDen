"""Ranks member-rank concern: promote / set / unassign + backfill.

Owns the two audit-logged member-rank endpoints and the lowest-rank
backfill — the only paths that write a member's rank alongside a
``rank_changed`` activity. The create / from-preset / enable-toggle
flows all lean on the same backfill, so ``is_rank_enabled`` and
``backfill_lowest_for_gym`` are session-scoped helpers the facade and
the presets concern compose (they run inside the caller's open
transaction, never opening one of their own).
"""

from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    RANK_CHANGED_ACTIVITY_TYPE,
    RankMemberResponse,
    RankPromoteMemberRequest,
    RankResponse,
    RankSetMemberRequest,
)
from src.ranks.service.ranks_base import RanksBase
from src.shared.sql_loader import load_sql


class RanksMembers(RanksBase):
    """Member-rank changes + the lowest-rank backfill."""

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

    async def is_rank_enabled(
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

    async def backfill_lowest_for_gym(
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
