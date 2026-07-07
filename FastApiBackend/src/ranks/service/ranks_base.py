"""Shared base for the ranks concern services.

Holds the direct DB pool and the reads every concern needs — the gym's
ordered ladder (one row per MAIN rank) and the gym's ``sub_rank_type`` —
plus the pure leaf-advance rule (``_next_leaf``). All reads run inside an
already-open session so they share the caller's transaction.
"""

from uuid import UUID

from schema.gym_rank import SubRankType, effective_sub_count
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.ranks import SQL_DIR
from src.ranks.schema.ranks_schema import RankResponse
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class RanksBase:
    """Common state + shared reads for every ranks service."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def _list_ranks_in_session(
        self,
        session: AsyncSession,
        gym_id: UUID,
    ) -> list[RankResponse]:
        """Ordered ladder for a gym (main rows), read in an open session."""
        sql = load_sql(SQL_DIR / "list_ranks.sql")
        rows = (
            (await session.execute(text(sql), {"gym_id": str(gym_id)}))
            .mappings()
            .all()
        )
        return [RankResponse(**dict(row)) for row in rows]

    async def _gym_sub_rank_type(
        self,
        session: AsyncSession,
        gym_id: UUID,
    ) -> SubRankType:
        """The gym's per-gym sub-rank type (stripes | div), in-session."""
        sql = load_sql(SQL_DIR / "get_gym_sub_rank_type.sql")
        row = (
            (await session.execute(text(sql), {"gym_id": str(gym_id)}))
            .mappings()
            .fetchone()
        )
        if not row:
            raise ValueError("Gym not found")
        return SubRankType(row["sub_rank_type"])

    @staticmethod
    def _effective_sub_count(
        rank: RankResponse,
        sub_rank_type: SubRankType,
    ) -> int:
        """The leaf count actually in effect for a rank.

        ``0`` whenever the gym disables sub-ranks (``sub_rank_type ==
        'none'``) — every rank then behaves as its own leaf — else the
        rank's stored ``sub_rank_count``. All leaf math (promotion, the
        leaf invariant, step denominators) reads THIS, never the raw
        column, so switching a gym to ``'none'`` is a pure view change
        over the persisted counts. Delegates to the shared
        ``schema.gym_rank.effective_sub_count`` — the single source of the
        rule, also used by the member-details service.
        """
        return effective_sub_count(sub_rank_type, rank.sub_rank_count)

    @staticmethod
    def _next_leaf(
        ladder: list[RankResponse],
        rank_id: UUID | None,
        sub_index: int | None,
        sub_rank_type: SubRankType,
    ) -> tuple[RankResponse, int | None]:
        """The next leaf up the ladder from a member's current leaf.

        Leaves per main rank use the EFFECTIVE sub-rank count (0 on a
        ``'none'`` gym): effective ``0`` is a single leaf (sub-index
        ``None``); otherwise ``0 .. count - 1``. A rank-less member
        advances to the lowest leaf. From a non-top sub-position, advance
        within the current main; from the top sub (or a subless main),
        advance to the base leaf of the next main. At the top main + top
        sub, raise ``ValueError("highest rank")``. On a ``'none'`` gym
        every rank is subless, so promotion is purely main-to-main.
        """
        if not ladder:
            raise ValueError("Gym has no ranks configured")

        def eff(rank: RankResponse) -> int:
            return RanksBase._effective_sub_count(rank, sub_rank_type)

        def base_leaf(rank: RankResponse) -> int | None:
            return 0 if eff(rank) > 0 else None

        if rank_id is None:
            first = ladder[0]
            return first, base_leaf(first)

        index = next(
            (
                i
                for i, rank in enumerate(ladder)
                if str(rank.rank_id) == str(rank_id)
            ),
            None,
        )
        # A current rank not in the ladder (e.g. just deleted) falls back
        # to the lowest leaf rather than failing.
        if index is None:
            first = ladder[0]
            return first, base_leaf(first)

        current = ladder[index]
        current_count = eff(current)
        if current_count > 0:
            # Defensive: a count>0 rank should never have a NULL sub_index
            # (the invariant), but treat NULL as "before the base leaf".
            cur = sub_index if sub_index is not None else -1
            if cur < current_count - 1:
                return current, cur + 1

        if index >= len(ladder) - 1:
            raise ValueError("Member is already at the highest rank")
        nxt = ladder[index + 1]
        return nxt, base_leaf(nxt)
