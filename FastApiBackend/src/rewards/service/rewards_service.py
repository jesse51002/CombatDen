"""Rewards CRUD service over ``gym_rewards``."""

import logging
from uuid import UUID

from schema.immutable_columns import GYM_REWARDS as GYM_REWARDS_IMMUTABLE
from sqlalchemy import text

from src.rewards import SQL_DIR
from src.rewards.schema.rewards_schema import (
    RewardCreateRequest,
    RewardListResponse,
    RewardResponse,
    RewardUpdateData,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class RewardsService:
    """Reward catalog CRUD."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        default_image_url: str,
    ) -> None:
        self._db_pool = db_pool
        # Every reward HAS an image (gym_rewards.image_url is NOT NULL): an
        # omitted image on create normalizes to this platform default
        # instead of ever writing NULL — mirrors ClassesCrudService.
        self._default_image_url = default_image_url

    async def create_reward(
        self,
        request: RewardCreateRequest,
    ) -> RewardResponse:
        """Insert a new reward row."""
        sql = load_sql(SQL_DIR / "insert_reward.sql")
        params = {
            "gym_id": str(request.gym_id),
            "title": request.title,
            "point_cost": request.point_cost,
            "image_url": request.image_url or self._default_image_url,
            "price_label": request.price_label,
        }
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise RuntimeError("INSERT did not return a row")
        return RewardResponse(**row)

    async def update_reward(
        self,
        reward_id: UUID,
        data: RewardUpdateData,
    ) -> RewardResponse:
        """Update mutable fields on a reward row."""
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(
            GYM_REWARDS_IMMUTABLE,
            set(update_fields.keys()),
        )

        set_clause = ", ".join(f"{col} = :{col}" for col in update_fields)
        sql = load_sql(
            SQL_DIR / "update_reward.sql",
            {"set_clause": set_clause},
        )
        params = {**update_fields, "reward_id": str(reward_id)}
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise ValueError("Reward not found")
        return RewardResponse(**row)

    async def deactivate_reward(self, reward_id: UUID) -> RewardResponse:
        """Soft-delete a reward by flipping ``is_active = false``."""
        return await self.update_reward(
            reward_id,
            RewardUpdateData(is_active=False),
        )

    async def get_reward(self, reward_id: UUID) -> RewardResponse:
        """Read a single reward row."""
        sql = load_sql(SQL_DIR / "get_reward.sql")
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), {"reward_id": str(reward_id)}))
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Reward not found")
        return RewardResponse(**row)

    async def list_rewards(
        self,
        gym_id: UUID,
        include_inactive: bool = False,
    ) -> RewardListResponse:
        """List rewards for a gym, ordered by ``point_cost`` ascending."""
        sql = load_sql(
            SQL_DIR / "list_rewards.sql",
            {"include_inactive": "TRUE" if include_inactive else "FALSE"},
        )
        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql), {"gym_id": str(gym_id)})).mappings().all()
        return RewardListResponse(
            items=[RewardResponse(**dict(row)) for row in rows],
        )
