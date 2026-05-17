"""Service for redeeming rewards and reading redemption history."""

import logging
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.rewards import SQL_DIR
from src.rewards.schema.rewards_schema import (
    RedemptionHistoryItem,
    RedemptionHistoryResponse,
    RedemptionResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class RewardsRedemptionService:
    """Redeem a reward (debit points + insert history row)."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def redeem(
        self,
        member_id: UUID,
        reward_id: UUID,
    ) -> RedemptionResponse:
        """Atomically decrement points_balance and insert a redemption row.

        The single SQL CTE locks both rows (``FOR UPDATE``) and
        only commits the redemption if the member has enough points
        and the reward is active. Returns 0 rows if either check
        fails.
        """
        sql = load_sql(SQL_DIR / "redeem_reward.sql")
        params = {
            "member_id": str(member_id),
            "reward_id": str(reward_id),
        }

        try:
            async with self._db_pool.session() as session:
                row = (await session.execute(text(sql), params)).mappings().fetchone()
                await session.commit()
        except IntegrityError as exc:
            # CHECK (points_balance >= 0) violation — same outcome as
            # an empty result set: insufficient points.
            logger.info(
                "Redemption rejected by check constraint: member_id=%s, reward_id=%s, exc=%s",
                member_id,
                reward_id,
                exc,
            )
            row = None

        if not row:
            raise ValueError("Redemption rejected: insufficient points or reward inactive")

        return RedemptionResponse(**row)

    async def history(self, member_id: UUID) -> RedemptionHistoryResponse:
        """Last 100 redemptions for a member."""
        sql = load_sql(SQL_DIR / "redemption_history.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {"member_id": str(member_id)},
                    )
                )
                .mappings()
                .all()
            )
        return RedemptionHistoryResponse(
            items=[RedemptionHistoryItem(**dict(row)) for row in rows],
        )
