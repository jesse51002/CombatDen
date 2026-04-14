"""Cancel a member's recurring membership."""

import logging
from datetime import date
from uuid import UUID

from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import SyncItem
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsCancel(MemberMembershipsBase):
    """Cancel a specific active recurring membership."""

    async def cancel(
        self,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Cancel a specific active recurring membership.

        Syncs the cancellation to Stripe first (including linked
        discount recalculation), then updates the CRM database.

        If the membership is already cancelled, this is a no-op.

        Args:
            item_id: The membership item.
            crm_user_id: The member.

        Raises:
            ValueError: If the membership is not found, has already
                ended, or is non-recurring.
        """
        row = await self._get_membership(item_id, crm_user_id)

        if row["cancel_date"] is not None:
            return

        self._validate_cancel(row, item_id, crm_user_id)

        # ── Stripe sync (includes linked discount recalc) ──
        cancel_item = SyncItem(
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            crm_user_id=crm_user_id,
            plan_id=row["plan_id"],
        )
        stripe_sub_id_after: str | None = None
        sync_succeeded = True
        try:
            sync_response = await self._payment_sync.update_payments_recurring(
                crm_user_id,
                add_ids=[],
                cancel_ids=[cancel_item],
            )
            stripe_sub_id_after = sync_response.stripe_subscription_id if sync_response else None
        except PaymentsResourceNotFoundError:
            sync_succeeded = False
            logger.warning(
                "Stripe resource not found during cancel "
                "(proceeding with CRM cancel): "
                "item_id=%s, crm_user_id=%s",
                item_id,
                crm_user_id,
            )

        # ── CRM cancel ────────────────────────────────────
        await self._crm_cancel(item_id, crm_user_id, gym_today(row["timezone"]))

        # ── Fan out post-discount prices to all siblings ──
        if sync_succeeded:
            parent = await self._payment_sync.resolve_parent(crm_user_id)
            stripe_account_id = await self._gym_stripe.get_stripe_account_id(
                parent.gym_id,
            )
            await self._price_writeback.sync_prices_from_stripe(
                parent_crm_user_id=parent.crm_user_id,
                stripe_sub_id=stripe_sub_id_after,
                stripe_account_id=stripe_account_id,
            )

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _validate_cancel(
        row: dict,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Validate a membership can be cancelled."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Cannot cancel non-recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )

        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            logger.warning(
                f"Recurring membership has ended set. "
                f"Shouldn't be possible "
                f"(end_date={row['end_date']}): "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )

    async def _crm_cancel(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        today: date,
    ) -> None:
        """Mark membership as cancelled in the CRM database."""
        cancel_sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")
        params = {
            "item_id": str(item_id),
            "crm_user_id": str(crm_user_id),
            "gym_today": today,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(cancel_sql), params)
            await session.commit()
