"""Service for managing member membership records on the CRM side."""

import logging
from datetime import date
from uuid import UUID

from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsService:
    """CRM-level operations on member_memberships rows.

    This service manages the CRM database state for memberships.
    It does NOT call Stripe — Stripe-level subscription operations
    live in PaymentsStripeSubscriptionService.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def cancel(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> None:
        """Cancel a specific active recurring membership.

        Sets cancel_date and end_date to the membership's
        next_due_date (end of current billing period). If
        next_due_date is NULL or in the past, falls back to today.

        If the membership is already cancelled, this is a no-op.

        Args:
            crm_user_id: The member.
            gym_id: The gym.
            plan_id: The membership plan to cancel.

        Raises:
            ValueError: If the membership is not found, has already
                ended, or is non-recurring.
        """
        get_sql = load_sql(SQL_DIR / "member_memberships_get.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(get_sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Membership not found: crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )

        if row["cancel_date"] is not None:
            return

        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Cannot cancel non-recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )

        if row["end_date"] is not None and row["end_date"] <= date.today():
            logger.warning(
                f"Canceling an already ended membership"
                f"(end_date={row['end_date']}): "
                f"crm_user_id={crm_user_id}, "
                f"gym_id={gym_id}, plan_id={plan_id}"
            )

        if row["next_due_date"] is None:
            logger.warning(
                "Cancelling membership with no next_due_date "
                "(falling back to today): crm_user_id=%s, "
                "gym_id=%s, plan_id=%s",
                crm_user_id,
                gym_id,
                plan_id,
            )

        cancel_sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")

        async with self._db_pool.session() as session:
            await session.execute(text(cancel_sql), params)
            await session.commit()
