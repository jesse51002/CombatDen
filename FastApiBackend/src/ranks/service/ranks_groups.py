"""Ranks whole-ladder concern: the two-phase reorder.

The reorder rewrites the entire ladder's main positions atomically. With
one row per MAIN rank, a group rename is just ``update_rank(name)`` and a
group delete is just ``delete_rank`` — there is no separate group op.
"""

import json

from sqlalchemy import text

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import (
    RankListResponse,
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
# non-deferrable UNIQUE (gym_id, main_rank_num_order) constraint
# mid-transaction, so the reorder guard rejects it up front (400).
REORDER_SHIFT_OFFSET = 100000


class RanksGroups(RanksBase):
    """Full-ladder two-phase reorder."""

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
        at every per-row check. Returns the reordered ladder.
        """
        ranks_json = json.dumps(
            [
                {
                    "rank_id": str(item.rank_id),
                    "main_rank_num_order": item.main_rank_num_order,
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
            sub_rank_type = await self._gym_sub_rank_type(
                session,
                request.gym_id,
            )
            await session.commit()

        return RankListResponse(items=items, sub_rank_type=sub_rank_type)

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

        positions = {item.main_rank_num_order for item in request.ranks}
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
