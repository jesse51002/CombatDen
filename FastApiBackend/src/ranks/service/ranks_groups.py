"""Ranks whole-ladder concern: two-phase reorder + group rename / delete.

Every operation here spans multiple rows of a gym's ladder atomically:
the reorder rewrites the entire order, and the group ops touch every row
of a ``(gym_id, main_rank_num_order)`` group in one statement rather than
fanning out per row on the client.
"""

import json
from uuid import UUID

from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    RankListResponse,
    RankRenameGroupRequest,
    RankReorderRequest,
    RankResponse,
)
from src.ranks.service.ranks_base import RanksBase
from src.shared.sql_loader import load_sql

# The two-phase reorder shifts every listed row's main order out of the
# target space by this amount (phase 1) before assigning final orders
# (phase 2). MUST match the ``+ 100000`` literal in
# ``sql/reorder_ranks_shift.sql``. A payload target at or above this value
# could collide with a still-shifted row during phase 2 and trip the
# non-deferrable UNIQUE (gym_id, main, sub) constraint mid-transaction, so
# the reorder guard rejects it up front (400) instead of letting it 500.
REORDER_SHIFT_OFFSET = 100000


class RanksGroups(RanksBase):
    """Full-ladder reorder + atomic whole-group rename / delete."""

    async def reorder_ranks(
        self,
        request: RankReorderRequest,
    ) -> RankListResponse:
        """Apply a full new ordering to a gym's ranks atomically.

        The payload must cover the gym's ENTIRE ladder — every rank
        exactly once, target positions unique, and no target main order
        at or above ``REORDER_SHIFT_OFFSET`` — validated up front so a
        bad payload is a clean ``ValueError`` (400) instead of a silent
        partial apply or a unique-constraint 500. Then a two-phase
        update in one transaction: shift every rank's main order into
        the ``+REORDER_SHIFT_OFFSET`` space, then assign final orders.
        This keeps the non-deferrable unique-order constraint satisfied
        at every per-row check. Returns the reordered list.
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

            items = await self._list_ranks_in_session(session, request.gym_id)
            await session.commit()

        return RankListResponse(items=items)

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

        # A target main order in the shift space would collide with a
        # still-shifted row during phase 2 (a transient UNIQUE violation
        # → 500). Reject it here so it fails as a clean 400 instead.
        if any(
            item.main_rank_num_order >= REORDER_SHIFT_OFFSET
            for item in request.ranks
        ):
            raise ValueError(
                "main_rank_num_order must be below "
                f"{REORDER_SHIFT_OFFSET} in a reorder payload"
            )

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
