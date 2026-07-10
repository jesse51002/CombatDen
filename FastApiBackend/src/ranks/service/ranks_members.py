"""Ranks member-rank concern: promote / set / unassign + backfill.

Owns the two audit-logged member-rank endpoints and the lowest-rank
backfill — the only paths that write a member's leaf (``current_rank_id``
+ ``current_sub_index``) alongside a ``rank_changed`` activity. The
create / from-preset / enable-toggle flows all lean on the same backfill,
so ``is_rank_enabled`` and ``backfill_lowest_for_gym`` are session-scoped
helpers the facade and the presets concern compose (they run inside the
caller's open transaction, never opening one of their own).
"""

from uuid import UUID

from schema.gym_rank import (
    SubRankType,
    rank_display_name,
    sub_rank_label,
)
from schema.member_activity import MemberActivityType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
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
        """Advance a member one leaf up the gym's ordered ladder.

        The next sub-position within the current main rank, else the
        base leaf of the next main rank. A rank-less member is assigned
        the lowest leaf (consistent with the enable-backfill). A member
        already at the top main + top sub raises
        ``ValueError("highest rank")``. The rank update and the audit
        activity share one transaction.
        """
        async with self._db_pool.session() as session:
            old_rank_id, old_sub_index, _ = await self._read_member_rank(
                session,
                request.member_id,
                request.gym_id,
            )

            ladder = await self._list_ranks_in_session(session, request.gym_id)
            if not ladder:
                raise ValueError("Gym has no ranks configured")
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            by_id = {str(rank.rank_id): rank for rank in ladder}
            old_rank = by_id.get(str(old_rank_id)) if old_rank_id else None

            new_rank, new_sub_index = self._next_leaf(
                ladder,
                old_rank_id,
                old_sub_index,
                sub_rank_type,
            )

            await self._apply_member_rank(
                session,
                member_id=request.member_id,
                gym_id=request.gym_id,
                old_rank_id=old_rank_id,
                old_sub_index=old_sub_index,
                new_rank_id=new_rank.rank_id,
                new_sub_index=new_sub_index,
                sub_rank_type=sub_rank_type,
                old_rank_name=old_rank.name if old_rank else None,
                new_rank_name=new_rank.name,
            )
            await session.commit()

        return self._member_response(
            request.member_id,
            new_rank,
            new_sub_index,
            sub_rank_type,
        )

    async def set_member_rank(
        self,
        request: RankSetMemberRequest,
    ) -> RankMemberResponse:
        """Set a member to an explicit leaf, or to no rank.

        Used for corrections, demotions, and assigning a rank-less
        member. A ``rank_id`` of ``None`` unassigns (both columns NULL).
        The target rank must belong to the member's gym; when it has
        sub-ranks, ``sub_index`` must be in ``[0, sub_rank_count - 1]``
        (else ``ValueError`` → 400); when it has none, ``sub_index`` is
        forced to ``None``. The rank update and the audit activity share
        one transaction.
        """
        async with self._db_pool.session() as session:
            old_rank_id, old_sub_index, _ = await self._read_member_rank(
                session,
                request.member_id,
                request.gym_id,
            )
            ladder = await self._list_ranks_in_session(session, request.gym_id)
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            by_id = {str(rank.rank_id): rank for rank in ladder}
            old_rank = by_id.get(str(old_rank_id)) if old_rank_id else None

            new_rank: RankResponse | None = None
            new_sub_index: int | None = None
            if request.rank_id is not None:
                new_rank = by_id.get(str(request.rank_id))
                if new_rank is None:
                    raise ValueError("Rank not found")
                new_sub_index = self._resolve_sub_index(
                    new_rank,
                    request.sub_index,
                    sub_rank_type,
                )

            await self._apply_member_rank(
                session,
                member_id=request.member_id,
                gym_id=request.gym_id,
                old_rank_id=old_rank_id,
                old_sub_index=old_sub_index,
                new_rank_id=request.rank_id,
                new_sub_index=new_sub_index,
                sub_rank_type=sub_rank_type,
                old_rank_name=old_rank.name if old_rank else None,
                new_rank_name=new_rank.name if new_rank else None,
            )
            await session.commit()

        return self._member_response(
            request.member_id,
            new_rank,
            new_sub_index,
            sub_rank_type,
        )

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
        """Assign the lowest leaf to every rank-less member of the gym.

        Pins each backfilled member to the lowest rank's base leaf
        (sub-index 0 when it has sub-ranks, else NULL) and writes one
        ``rank_changed`` activity per member with the Python-derived
        display name, so progress counts from the backfill moment (not
        the member's join date). No-op when the gym has no ranks.
        """
        ladder = await self._list_ranks_in_session(session, gym_id)
        new_rank_name: str | None = None
        if ladder:
            sub_rank_type = await self._gym_sub_rank_type(session, gym_id)
            lowest = ladder[0]
            base_index = (
                0
                if self._effective_sub_count(lowest, sub_rank_type) > 0
                else None
            )
            new_rank_name = rank_display_name(
                lowest.name,
                sub_rank_type,
                base_index,
            )
        sql = load_sql(SQL_DIR / "backfill_lowest_rank.sql")
        await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "activity_type": MemberActivityType.rank_changed.value,
                "new_rank_name": new_rank_name,
            },
        )

    async def reassign_members_to_neighbor_in_session(
        self,
        session: AsyncSession,
        *,
        old_rank_id: UUID,
        new_rank_id: UUID | None,
        gym_id: UUID,
    ) -> None:
        """Move every member off a deleted rank onto its replacement.

        Pins them to the replacement's BASE leaf (sub-index 0 when it has
        sub-ranks, else NULL — reading the EFFECTIVE count), or NULL when
        the deleted rank was the gym's only rank. Silent — a deletion is
        not a promotion, so no ``rank_changed`` activity is written. Runs
        inside the caller's open transaction (the same one that then
        deletes the rank row), so a rollback undoes both. This keeps the
        member write on ``RanksMembers`` — the single member-writing path.
        """
        sql = load_sql(SQL_DIR / "reassign_members_rank.sql")
        await session.execute(
            text(sql),
            {
                "old_rank_id": str(old_rank_id),
                "new_rank_id": str(new_rank_id) if new_rank_id else None,
                "gym_id": str(gym_id),
            },
        )

    async def reconcile_sub_index_for_gym(
        self,
        gym_id: UUID,
        sub_rank_type: SubRankType,
    ) -> None:
        """Own-session reconcile of members after a gym sub_rank_type change.

        Opens and commits its own session — the gym-update path
        (``GymsService.update_gym``) calls this AFTER the gyms row is
        already committed, mirroring how the timezone re-mint runs after
        the gyms write. The in-session flows (``from_preset``) call
        ``reconcile_sub_index_in_session`` directly instead.
        """
        async with self._db_pool.session() as session:
            await self.reconcile_sub_index_in_session(
                session,
                gym_id,
                sub_rank_type,
            )
            await session.commit()

    async def reconcile_sub_index_in_session(
        self,
        session: AsyncSession,
        gym_id: UUID,
        sub_rank_type: SubRankType,
    ) -> None:
        """Re-fit every member's ``current_sub_index`` to the new style.

        Keeps the leaf invariant valid without a destructive rewrite:
        switching to ``'none'`` clears every sub-index; switching to
        ``'stripes'`` / ``'div'`` fills a NULL sub-index (coming from
        ``'none'``) with the base leaf ``0`` on a rank that has
        sub-ranks, preserves an already-valid index (a pure
        stripes↔div re-label never moves a member), and clears it on a
        subless rank. Never touches the persisted ``sub_rank_count`` /
        ``sub_rank_image_overrides``. No ``rank_changed`` activity — a
        style toggle is a re-fit, not a promotion, so the progress
        anchor must not reset.
        """
        sql = load_sql(SQL_DIR / "reconcile_member_sub_index_for_gym.sql")
        await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "sub_rank_type": sub_rank_type.value,
            },
        )

    @staticmethod
    def _resolve_sub_index(
        rank: RankResponse,
        sub_index: int | None,
        sub_rank_type: SubRankType,
    ) -> int | None:
        """Validate / coerce a requested sub-index against the rank.

        Uses the EFFECTIVE sub-rank count (0 on a ``'none'`` gym): an
        effective ``count > 0`` requires ``sub_index`` in range; an
        effective-subless rank (including every rank on a ``'none'`` gym)
        forces ``None`` (a stray index is silently ignored, matching the
        subless-rank invariant style).
        """
        effective_count = RanksMembers._effective_sub_count(rank, sub_rank_type)
        if effective_count > 0:
            if sub_index is None or not (0 <= sub_index <= effective_count - 1):
                raise ValueError(
                    "sub_index must be in "
                    f"[0, {effective_count - 1}] for this rank"
                )
            return sub_index
        return None

    @staticmethod
    def _member_response(
        member_id: UUID,
        new_rank: RankResponse | None,
        new_sub_index: int | None,
        sub_rank_type: SubRankType,
    ) -> RankMemberResponse:
        """Build the promote / set response with derived sub labels."""
        if new_rank is None:
            return RankMemberResponse(member_id=member_id)
        return RankMemberResponse(
            member_id=member_id,
            new_rank=new_rank,
            new_sub_index=new_sub_index,
            new_sub_label=sub_rank_label(sub_rank_type, new_sub_index),
            new_display_name=rank_display_name(
                new_rank.name,
                sub_rank_type,
                new_sub_index,
            ),
        )

    async def _read_member_rank(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
    ) -> tuple[UUID | None, int | None, UUID]:
        """Read a member's current leaf, asserting gym ownership."""
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
        return row["current_rank_id"], row["current_sub_index"], row["gym_id"]

    async def _apply_member_rank(
        self,
        session: AsyncSession,
        *,
        member_id: UUID,
        gym_id: UUID,
        old_rank_id: UUID | None,
        old_sub_index: int | None,
        new_rank_id: UUID | None,
        new_sub_index: int | None,
        sub_rank_type: SubRankType,
        old_rank_name: str | None,
        new_rank_name: str | None,
    ) -> None:
        """Set a member's leaf and log the change, in one session.

        The audit activity is written whenever the leaf actually moves —
        a sub-only promotion logs too. Only a no-op (BOTH rank_id AND
        sub_index unchanged) leaves no row. Both display names are
        derived here via ``rank_display_name`` (NULL for an unassigned
        old / new leaf).
        """
        set_sql = load_sql(SQL_DIR / "set_member_rank.sql")
        updated = (
            (
                await session.execute(
                    text(set_sql),
                    {
                        "new_rank_id": str(new_rank_id) if new_rank_id else None,
                        "new_sub_index": new_sub_index,
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

        if str(old_rank_id) == str(new_rank_id) and old_sub_index == new_sub_index:
            return

        old_display = (
            rank_display_name(old_rank_name, sub_rank_type, old_sub_index)
            if old_rank_name is not None
            else None
        )
        new_display = (
            rank_display_name(new_rank_name, sub_rank_type, new_sub_index)
            if new_rank_name is not None
            else None
        )

        activity_sql = load_sql(SQL_DIR / "insert_rank_activity.sql")
        await session.execute(
            text(activity_sql),
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "old_rank_id": str(old_rank_id) if old_rank_id else None,
                "new_rank_id": str(new_rank_id) if new_rank_id else None,
                "old_rank_name": old_display,
                "new_rank_name": new_display,
                "activity_type": MemberActivityType.rank_changed.value,
            },
        )
