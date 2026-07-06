"""Ranks read concern: the two paginated member-board reads.

``list_ready_to_promote`` powers the Ranks-tab proximity board (ranked,
active-membership, not-top-of-ladder members sorted by closeness to their
next leaf); ``list_members_in_rank`` powers the rank-detail roster. Both
are DB-paginated (``COUNT(*) OVER()`` total + ``start_index`` / ``count``)
and derive each row's sub-rank label from the gym's ``sub_rank_type``.
"""

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
        """Members currently on one main rank, paginated by sub-index."""
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
