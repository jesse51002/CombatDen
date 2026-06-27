"""Soft-delete a membership plan in CRM and Stripe."""

from __future__ import annotations

import logging
from uuid import UUID

from sqlalchemy import text

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipDeactivateRequest,
)
from src.plans import SQL_DIR
from src.plans.service.plans_base import (
    MembershipPlansBase,
)
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembershipPlansDelete(MembershipPlansBase):
    """Soft-delete a membership plan in CRM and Stripe."""

    async def delete_plan(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Deactivate the Stripe product then soft-delete in CRM.

        Args:
            plan_id: The plan to delete.
            gym_id: The gym owning the plan.

        Raises:
            ValueError: If the plan is not found, or it still has active
                members (their billing references it — move them off first).
        """
        existing = await self._get_plan(plan_id, gym_id)

        # A plan with active members can't be deleted — their memberships
        # bill against it. Reject before touching Stripe or the DB.
        active_members = await self._count_active_members(plan_id, gym_id)
        if active_members > 0:
            raise ValueError(
                f"Cannot delete a plan with {active_members} active "
                f"member(s); move them to another plan first."
            )

        stripe_product_id = existing.get("stripe_product_id")
        if stripe_product_id:
            stripe_account_id = await self._gym_stripe.get_stripe_account_id(
                gym_id,
            )

            # ── Stripe first ──────────────────────────────────
            try:
                await self._stripe_memberships.deactivate_membership(
                    PaymentsMembershipDeactivateRequest(
                        stripe_product_id=stripe_product_id,
                    ),
                    stripe_account_id,
                )
            except PaymentsResourceNotFoundError as exc:
                if exc.resource_type != StripeResourceType.product:
                    raise
                logger.warning(
                    "Stripe product %s already gone — proceeding with DB soft-delete",
                    stripe_product_id,
                )

        # ── CRM soft-delete ───────────────────────────────────
        delete_sql = load_sql(SQL_DIR / "membership_plans_delete.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(delete_sql),
                {"plan_id": str(plan_id), "gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Plan {plan_id} not found")
            await session.commit()

    async def _count_active_members(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> int:
        """How many of the plan's members hold a LIVE (active) membership."""
        sql = load_sql(SQL_DIR / "membership_plans_active_member_count.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"plan_id": str(plan_id), "gym_id": str(gym_id)},
            )
            return int(result.scalar_one())
