"""Upgrade a membership to its plan's currently active price."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import SyncItem
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsUpdatePrice(MemberMembershipsBase):
    """Move a membership onto its plan's active price tier."""

    async def update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
        prorate: bool = False,
    ) -> None:
        """Upgrade a membership to its plan's active price.

        The caller does not choose the target price — the
        service always targets the one ``membership_plan_prices``
        row with ``is_active = true`` for the plan. If the
        membership is already on that price the CRM row is left
        alone, but Stripe is still re-synced defensively.

        Args:
            item_id: The membership item.
            member_id: The member.
            idempotency_key: Stripe idempotency key.
            prorate: Whether to prorate the change.

        Raises:
            ValueError: If membership not found, cancelled, ended,
                or no active price exists for the plan.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )

        already_active = row["price_id"] == active_price["price_id"]

        await self._sync_to_active_price(
            row=row,
            member_id=member_id,
            active_price=active_price,
            prorate=prorate,
            idempotency_key=idempotency_key,
        )

        if already_active:
            return

        await self._crm_update_price(
            item_id=item_id,
            member_id=member_id,
            new_price_id=active_price["price_id"],
            total_price=active_price["price"],
        )

    async def preview_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview upgrading a membership to the plan's active price.

        Runs every validation ``update_price`` runs and returns
        the Stripe invoice preview for the swap — or a zero-delta
        preview when the membership is already on the active price.

        Raises:
            ValueError: Same conditions as ``update_price``.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )

        cancel_item, add_item = self._build_sync_items(
            row=row,
            member_id=member_id,
            active_price=active_price,
            prorate=prorate,
        )
        return await self._payment_sync.preview_update_payments_recurring(
            member_id,
            add_ids=[add_item],
            cancel_ids=[cancel_item],
        )

    # ── Private ────────────────────────────────────────────────

    async def _sync_to_active_price(
        self,
        row: dict,
        member_id: UUID,
        active_price: dict,
        prorate: bool,
        idempotency_key: UUID,
    ) -> None:
        """Run the Stripe re-sync for the active price."""
        cancel_item, add_item = self._build_sync_items(
            row=row,
            member_id=member_id,
            active_price=active_price,
            prorate=prorate,
        )
        await self._payment_sync.update_payments_recurring(
            member_id,
            add_ids=[add_item],
            cancel_ids=[cancel_item],
            idempotency_key=idempotency_key,
        )

    @staticmethod
    def _build_sync_items(
        row: dict,
        member_id: UUID,
        active_price: dict,
        prorate: bool,
    ) -> tuple[SyncItem, SyncItem]:
        """Build (cancel_item, add_item) for the payment sync call."""
        if not row["stripe_price_id"]:
            raise ValueError(
                f"Membership missing stripe_price_id for item_id={row.get('item_id')}"
            )
        if not row["stripe_item_id"]:
            raise ValueError(f"Membership missing stripe_item_id for item_id={row.get('item_id')}")
        cancel_item = SyncItem(
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            member_id=member_id,
            plan_id=row["plan_id"],
        )
        # Discounts no longer thread through the sync items. The applied
        # snapshots stay frozen on this membership's item_id (unchanged by a
        # price swap — only price_id/total_price change), so the sync-time
        # coupon step re-attaches them to the consolidated line from the
        # snapshot table.
        add_item = SyncItem(
            stripe_price_id=active_price["stripe_price_id"],
            member_id=member_id,
            plan_id=row["plan_id"],
            prorate=prorate,
        )
        return cancel_item, add_item

    @staticmethod
    def _validate_update_price(
        row: dict,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate a membership can have its price updated."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot update price on cancelled membership: "
                f"item_id={item_id}, member_id={member_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            raise ValueError(
                f"Cannot update price on ended membership: "
                f"item_id={item_id}, member_id={member_id}"
            )

    async def _get_active_price_for_plan(
        self,
        gym_id: UUID,
        plan_id: UUID,
    ) -> dict:
        """Fetch the plan's currently active price row.

        Raises:
            ValueError: If no active price exists for the plan.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_active_price.sql")
        params = {
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"No active price for plan: plan_id={plan_id}, gym_id={gym_id}")
        return dict(row)

    async def _crm_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        new_price_id: UUID,
        total_price: int,
    ) -> None:
        """Update price_id and total_price on a membership."""
        sql = load_sql(SQL_DIR / "member_memberships_update_price.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
            "new_price_id": str(new_price_id),
            "total_price": total_price,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
