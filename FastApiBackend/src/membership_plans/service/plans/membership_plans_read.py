"""Read operations for membership plans."""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.membership_plans import SQL_DIR
from src.membership_plans.membership_plans_schemas import (
    MembershipPlanResponse,
)
from src.membership_plans.service.plans.membership_plans_base import (
    MembershipPlansBase,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembershipPlansRead(MembershipPlansBase):
    """List and get membership plans."""

    async def list_plans(
        self,
        gym_id: UUID,
    ) -> list[MembershipPlanResponse]:
        """List all non-deleted plans for a gym with active prices.

        Args:
            gym_id: The gym to list plans for.

        Returns:
            Plans ordered by created_at descending.
        """
        sql = load_sql(SQL_DIR / "membership_plans_list.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            rows = result.mappings().fetchall()

        return [
            self._build_plan_response(
                dict(row),
                active_price=self._extract_active_price(dict(row)),
            )
            for row in rows
        ]

    async def get_plan(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> MembershipPlanResponse:
        """Get a single plan with its active price.

        Args:
            plan_id: The plan to fetch.
            gym_id: The gym owning the plan.

        Returns:
            Plan with active price.

        Raises:
            ValueError: If the plan is not found.
        """
        plan_row = await self._get_plan(plan_id, gym_id)
        return self._build_plan_response(
            plan_row,
            active_price=self._extract_active_price(plan_row),
        )
