"""Update the price tier of an existing membership."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import SyncItem
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsUpdatePrice(MemberMembershipsBase):
    """Switch a membership to a different price tier."""

    async def update_price(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        new_price_id: UUID,
        prorate: bool = False,
    ) -> None:
        """Update the price tier of an existing membership.

        Swaps the old price for the new one in Stripe, then
        updates the CRM row.

        Args:
            item_id: The membership item.
            crm_user_id: The member.
            new_price_id: The new price tier.
            prorate: Whether to prorate the change.

        Raises:
            ValueError: If membership not found, cancelled, ended,
                or new price invalid.
        """
        row = await self._get_membership(item_id, crm_user_id)
        self._validate_update_price(row, item_id, crm_user_id)

        new_price = await self._get_price_for_plan(
            row["gym_id"],
            row["plan_id"],
            new_price_id,
        )

        # ── Stripe first ──────────────────────────────────
        if not row["stripe_price_id"]:
            raise ValueError(f"Membership missing stripe_price_id for item_id={item_id}")
        if not row["stripe_item_id"]:
            raise ValueError(f"Membership missing stripe_item_id for item_id={item_id}")
        cancel_item = SyncItem(
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            crm_user_id=crm_user_id,
            plan_id=row["plan_id"],
        )
        add_item = SyncItem(
            stripe_price_id=new_price["stripe_price_id"],
            crm_user_id=crm_user_id,
            plan_id=row["plan_id"],
            prorate=prorate,
        )
        response = await self._payment_sync.update_payments_recurring(
            crm_user_id,
            add_ids=[add_item],
            cancel_ids=[cancel_item],
        )
        stripe_sub_id_after: str | None = None
        if response:
            self._extract_stripe_item_id(
                response,
                new_price["stripe_price_id"],
            )
            stripe_sub_id_after = response.stripe_subscription_id

        # ── CRM update ────────────────────────────────────
        await self._crm_update_price(
            item_id=item_id,
            crm_user_id=crm_user_id,
            new_price_id=new_price_id,
            total_price=new_price["price"],
        )

        # ── Fan out post-discount prices to all siblings ──
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
    def _validate_update_price(
        row: dict,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Validate a membership can have its price updated."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot update price on cancelled membership: "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            raise ValueError(
                f"Cannot update price on ended membership: "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )

    async def _get_price_for_plan(
        self,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
    ) -> dict:
        """Validate a new price exists and is active for the plan.

        Raises:
            ValueError: If not found or not active.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_price.sql")
        params = {
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
            "price_id": str(price_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Price not found for plan: price_id={price_id}, "
                f"plan_id={plan_id}, gym_id={gym_id}"
            )
        if not row["is_active"]:
            raise ValueError(f"Price is not active: price_id={price_id}")
        return dict(row)

    async def _crm_update_price(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        new_price_id: UUID,
        total_price: int,
    ) -> None:
        """Update price_id and total_price on a membership."""
        sql = load_sql(SQL_DIR / "member_memberships_update_price.sql")
        params = {
            "item_id": str(item_id),
            "crm_user_id": str(crm_user_id),
            "new_price_id": str(new_price_id),
            "total_price": total_price,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
