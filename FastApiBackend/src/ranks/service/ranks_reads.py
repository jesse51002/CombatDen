"""Ranks read concern: the paginated member-board reads + the
per-sub-index count.

``list_ready_to_promote`` powers the Ranks-tab proximity board (ranked,
active-membership, not-top-of-ladder members sorted by percentage complete
toward their next leaf); ``list_members_in_rank`` powers the rank-detail
roster (the same percentage order, all members). Both are DB-paginated
(``COUNT(*) OVER()`` total + ``start_index`` / ``count``) and derive each
row's sub-rank label from the gym's ``sub_rank_type``.
``count_members_by_sub_index`` is the rank-detail per-sub-position
breakdown (total on the rank + a sparse count per sub-index).
"""

from uuid import UUID

from schema.gym_rank import SubRankType, sub_rank_label
from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    MembersInRankRequest,
    MembersInRankResponse,
    MembersInRankRow,
    MembersReadyToPromoteRequest,
    MembersReadyToPromoteResponse,
    MembersReadyToPromoteRow,
    RankSubRankCount,
    RankSubRankCountsResponse,
)
from src.ranks.service.ranks_base import RanksBase
from src.shared.sql_loader import load_sql


class RanksReads(RanksBase):
    """Paginated ready-to-promote + members-in-rank reads."""

    async def list_ready_to_promote(
        self,
        request: MembersReadyToPromoteRequest,
    ) -> MembersReadyToPromoteResponse:
        """Members closest to their next promotion, paginated."""
        sql = load_sql(SQL_DIR / "list_members_ready_to_promote.sql")
        async with self._db_pool.session() as session:
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(request.gym_id),
                            "count": request.count,
                            "start_index": request.start_index,
                        },
                    )
                )
                .mappings()
                .all()
            )

        items = [
            self._ready_row(row, sub_rank_type) for row in rows
        ]
        total = rows[0]["total_count"] if rows else 0
        return MembersReadyToPromoteResponse(items=items, total_count=total)

    async def list_members_in_rank(
        self,
        request: MembersInRankRequest,
    ) -> MembersInRankResponse:
        """Members on one main rank, paginated, percentage-sorted.

        Ordered by percentage complete toward the next leaf
        (proportionally closest first), the same order as the
        ready-to-promote board; every member on the rank is returned.
        """
        sql = load_sql(SQL_DIR / "list_members_in_rank.sql")
        async with self._db_pool.session() as session:
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(request.gym_id),
                            "rank_id": str(request.rank_id),
                            "count": request.count,
                            "start_index": request.start_index,
                        },
                    )
                )
                .mappings()
                .all()
            )

        items = [
            self._in_rank_row(row, sub_rank_type) for row in rows
        ]
        total = rows[0]["total_count"] if rows else 0
        return MembersInRankResponse(items=items, total_count=total)

    async def count_members_by_sub_index(
        self,
        gym_id: UUID,
        rank_id: UUID,
    ) -> RankSubRankCountsResponse:
        """Member counts per sub-position for one main rank.

        Returns the total on the rank plus a SPARSE per-sub-index
        breakdown (only sub-indices with at least one member — the CRM
        fills 0 for empty slots from the rank's ``sub_rank_count``). On a
        ``'none'`` gym members carry a NULL sub-index, so ``counts`` is a
        single ``{null, total}`` row. ``total_count`` is summed in Python
        from the fetched rows.
        """
        sql = load_sql(SQL_DIR / "count_members_by_sub_index.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(gym_id),
                            "rank_id": str(rank_id),
                        },
                    )
                )
                .mappings()
                .all()
            )

        counts = [
            RankSubRankCount(sub_index=row["sub_index"], count=row["count"])
            for row in rows
        ]
        total = sum(item.count for item in counts)
        return RankSubRankCountsResponse(total_count=total, counts=counts)

    async def next_leaf_image_url(
        self,
        gym_id: UUID,
        rank_id: UUID | None,
        sub_index: int | None,
    ) -> str | None:
        """The belt image of the leaf ABOVE a member's current leaf.

        Reuses the domain's one leaf-advance rule (``RanksBase._next_leaf``
        over the ``main_rank_num_order`` ladder + the gym's EFFECTIVE
        sub-rank count) rather than deriving "next rank" a second time, and
        resolves the image with the same precedence the current leaf uses:
        the target leaf's ``sub_rank_image_overrides[sub_index]`` if
        present, else the main rank's ``image_url``.

        Args:
            gym_id: The member's gym.
            rank_id: The member's current main rank (``None`` = unranked,
                whose next leaf is the ladder's lowest).
            sub_index: The member's current sub-position, or ``None``.

        Returns:
            The next leaf's belt image URL, or ``None`` when there is no
            next leaf (the member is at the highest rank, or the gym has no
            ladder) or that leaf carries no image.
        """
        async with self._db_pool.session() as session:
            sub_rank_type = await self._gym_sub_rank_type(session, gym_id)
            ladder = await self._list_ranks_in_session(session, gym_id)

        try:
            rank, leaf_index = self._next_leaf(
                ladder,
                rank_id,
                sub_index,
                sub_rank_type,
            )
        except ValueError:
            # No next leaf: top of the ladder, or no ranks configured.
            return None

        if leaf_index is not None:
            override = (rank.sub_rank_image_overrides or {}).get(
                str(leaf_index),
            )
            if override:
                return override
        return rank.image_url

    @staticmethod
    def _ready_row(
        row: dict,
        sub_rank_type: SubRankType,
    ) -> MembersReadyToPromoteRow:
        """Map a ready-to-promote SQL row + derive its sub label."""
        return MembersReadyToPromoteRow(
            member_id=row["member_id"],
            name=row["name"],
            avatar_url=row["avatar_url"],
            main_rank_id=row["main_rank_id"],
            main_name=row["main_name"],
            current_sub_index=row["current_sub_index"],
            sub_label=sub_rank_label(sub_rank_type, row["current_sub_index"]),
            image_url=row["image_url"],
            classes_since=row["classes_since"],
            step_denominator=row["step_denominator"],
        )

    @staticmethod
    def _in_rank_row(
        row: dict,
        sub_rank_type: SubRankType,
    ) -> MembersInRankRow:
        """Map a members-in-rank SQL row + derive its sub label."""
        return MembersInRankRow(
            member_id=row["member_id"],
            name=row["name"],
            avatar_url=row["avatar_url"],
            current_sub_index=row["current_sub_index"],
            sub_label=sub_rank_label(sub_rank_type, row["current_sub_index"]),
            classes_since=row["classes_since"],
            step_denominator=row["step_denominator"],
        )
