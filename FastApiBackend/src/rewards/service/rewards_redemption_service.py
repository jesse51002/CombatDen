"""Service for redeeming rewards and managing redemption lifecycle."""

import logging
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from src.rewards import SQL_DIR
from src.rewards.schema.rewards_schema import (
    PendingRedemptionItem,
    PendingRedemptionListResponse,
    RedemptionHistoryItem,
    RedemptionHistoryResponse,
    RedemptionResponse,
    RedemptionTransitionResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class RedemptionAlreadyDecidedError(Exception):
    """Raised when an approve/reject is attempted on a non-pending redemption."""


class RewardsRedemptionService:
    """Redeem rewards and manage the approval lifecycle."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def redeem(
        self,
        member_id: UUID,
        reward_id: UUID,
        auto_approve: bool = False,
    ) -> RedemptionResponse:
        """Atomically decrement points_balance and insert a redemption row.

        When ``auto_approve`` is False the row is inserted with
        ``status='pending'``; when True it is immediately ``status='approved'``
        with ``resolved_at=now()``.  Returns 0 rows (→ ValueError) if the member
        has insufficient points or the reward is inactive.
        """
        sql = load_sql(SQL_DIR / "redeem_reward.sql")
        status_value = "approved" if auto_approve else "pending"
        params = {
            "member_id": str(member_id),
            "reward_id": str(reward_id),
            "status": status_value,
        }

        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            logger.info(
                "Redemption rejected by check constraint: "
                "member_id=%s, reward_id=%s, exc=%s",
                member_id,
                reward_id,
                exc,
            )
            row = None

        if not row:
            raise ValueError(
                "Redemption rejected: insufficient points or reward inactive"
            )

        return RedemptionResponse(**row)

    async def redeem_override(
        self,
        member_id: UUID,
        reward_id: UUID,
    ) -> RedemptionResponse:
        """Staff override: debit LEAST(points_balance, point_cost), always approve.

        Drops the points sufficiency guard so the redemption is always written
        (balance drains to zero; shortfall is comped). Still requires the
        reward to be active.
        """
        sql = load_sql(SQL_DIR / "redeem_reward_override.sql")
        params = {
            "member_id": str(member_id),
            "reward_id": str(reward_id),
        }

        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            logger.info(
                "Override redemption rejected by constraint: "
                "member_id=%s, reward_id=%s, exc=%s",
                member_id,
                reward_id,
                exc,
            )
            row = None

        if not row:
            raise ValueError("Redemption rejected: reward is inactive")

        return RedemptionResponse(**row)

    async def get_redemption_for_auth(self, redemption_id: UUID) -> dict:
        """Return gym_id, member_id, status for a redemption (auth + conflict check).

        Raises:
            ValueError: if the redemption does not exist.
        """
        sql = load_sql(SQL_DIR / "get_redemption.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {"redemption_id": str(redemption_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Redemption not found")
        return dict(row)

    async def approve(self, redemption_id: UUID) -> RedemptionTransitionResponse:
        """Approve a pending redemption.

        Raises:
            RedemptionAlreadyDecidedError: if the row is not pending.
        """
        sql = load_sql(SQL_DIR / "approve_redemption.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {"redemption_id": str(redemption_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
            await session.commit()

        if not row:
            raise RedemptionAlreadyDecidedError(
                "Redemption is not pending or does not exist"
            )
        return RedemptionTransitionResponse(**row)

    async def reject(self, redemption_id: UUID) -> RedemptionTransitionResponse:
        """Reject a pending redemption and refund the member's points.

        Raises:
            RedemptionAlreadyDecidedError: if the row is not pending.
        """
        sql = load_sql(SQL_DIR / "reject_redemption.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {"redemption_id": str(redemption_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
            await session.commit()

        if not row:
            raise RedemptionAlreadyDecidedError(
                "Redemption is not pending or does not exist"
            )
        return RedemptionTransitionResponse(**row)

    async def list_pending(
        self,
        gym_id: UUID,
        limit: int = 100,
        offset: int = 0,
    ) -> PendingRedemptionListResponse:
        """Return a page of pending redemptions for a gym, oldest first."""
        sql = load_sql(SQL_DIR / "list_pending_redemptions.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {"gym_id": str(gym_id), "limit": limit, "offset": offset},
                    )
                )
                .mappings()
                .all()
            )
        total = rows[0]["total"] if rows else 0
        return PendingRedemptionListResponse(
            # The window-count `total` column rides on every row; Pydantic's
            # default extra="ignore" drops it, no per-row filtering needed.
            items=[PendingRedemptionItem(**dict(row)) for row in rows],
            total=total,
        )

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
