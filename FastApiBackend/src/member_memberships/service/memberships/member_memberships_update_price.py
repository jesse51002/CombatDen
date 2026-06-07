"""Upgrade a membership to its plan's currently active price (DB-first)."""

import logging
from uuid import UUID

from schema.member_membership import StripeSyncStatus
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.db_first_helpers import staged_preview, sync_or_revert
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
        """Upgrade a membership to its plan's active price (DB-first).

        The caller does not choose the target price — the service always targets
        the one ``membership_plan_prices`` row with ``is_active = true`` for the
        plan. If the membership is already on that price the CRM row is left
        alone and Stripe is re-synced defensively. Otherwise the new ``price_id``
        is written to the DB FIRST, then the param-less sync migrates the Stripe
        line; the migration is **verified** (the row's ``stripe_item_id`` must
        move to the new price's line) and the ``price_id`` is reverted if the
        sync did not confirm, so the DB stays in sync with Stripe.

        Args:
            item_id: The membership item.
            member_id: The member.
            idempotency_key: Stripe idempotency key.
            prorate: Whether to prorate the change (``always_invoice`` vs
                ``none``).

        Raises:
            ValueError: If membership not found, cancelled, ended,
                or no active price exists for the plan.
            SyncNotConfirmedError: If the migration could not be confirmed on
                Stripe (the DB change has been reverted).
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )

        proration_behavior = "always_invoice" if prorate else "none"

        if row["price_id"] == active_price["price_id"]:
            # Already on the active price — no DB change to make. Re-sync
            # defensively (idempotent); nothing to verify or revert.
            await self._payment_sync.update_payments_recurring(
                member_id,
                idempotency_key=idempotency_key,
                proration_behavior=proration_behavior,
            )
            return

        old_price_id = row["price_id"]
        old_total_price = row["price"]

        # Pre-sync: converge the family to a clean DB↔Stripe baseline first.
        await self._pre_sync_payments(member_id)

        # ── DB-first: write new price + stage 'migrating', THEN converge Stripe ──
        # 'migrating' lets the writeback move the (otherwise immutable)
        # stripe_item_id to the new price's line, and lets a failed migration
        # revert. The writeback stamps the row back to 'applied' on success.
        await self._crm_update_price(
            item_id=item_id,
            member_id=member_id,
            new_price_id=active_price["price_id"],
            total_price=active_price["price"],
            sync_status=StripeSyncStatus.migrating,
        )

        async def _verify() -> bool:
            # Success = the writeback stamped the row back to 'applied'
            # (migrating -> applied); still 'migrating' means the sync did not
            # confirm the line move.
            status = await self._get_sync_status(item_id, member_id)
            return status == StripeSyncStatus.applied

        await sync_or_revert(
            sync_fn=lambda: self._payment_sync.update_payments_recurring(
                member_id,
                idempotency_key=idempotency_key,
                proration_behavior=proration_behavior,
            ),
            revert_fn=lambda: self._crm_update_price(
                item_id=item_id,
                member_id=member_id,
                new_price_id=old_price_id,
                total_price=old_total_price,
                sync_status=StripeSyncStatus.applied,
            ),
            entity_name="member_membership",
            crm_pk=str(item_id),
            verify_fn=_verify,
        )

    async def preview_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview upgrading a membership to the plan's active price.

        Runs every validation ``update_price`` runs and returns the Stripe
        invoice preview.

        Raises:
            ValueError: Same conditions as ``update_price``.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )
        proration_behavior = "always_invoice" if prorate else "none"

        if row["price_id"] == active_price["price_id"]:
            # Already on the active price — nothing to stage; preview as-is.
            return await self._payment_sync.preview_update_payments_recurring(
                member_id,
                proration_behavior=proration_behavior,
            )

        old_price_id = row["price_id"]
        old_total_price = row["price"]

        # Temporarily flip the row to the new price so the preview build groups it
        # under the new line, then restore. Status stays 'applied' (dry-run, no
        # real migration). Window bounded by `finally`; the per-parent lock (#25)
        # closes the race vs a concurrent real sync (TODO).
        return await staged_preview(
            stage_fn=lambda: self._crm_update_price(
                item_id,
                member_id,
                active_price["price_id"],
                active_price["price"],
                StripeSyncStatus.applied,
            ),
            cleanup_fn=lambda: self._crm_update_price(
                item_id,
                member_id,
                old_price_id,
                old_total_price,
                StripeSyncStatus.applied,
            ),
            preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                member_id,
                proration_behavior=proration_behavior,
            ),
        )

    # ── Private ────────────────────────────────────────────────

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
        sync_status: StripeSyncStatus,
    ) -> None:
        """Update price_id + total_price + staged sync status on a membership.

        Used both for the forward migration (stage ``migrating``) and the revert
        (restore the old price + ``applied``). Leaves ``stripe_item_id`` intact.
        """
        sql = load_sql(SQL_DIR / "member_memberships_update_price.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
            "new_price_id": str(new_price_id),
            "total_price": total_price,
            "sync_status": sync_status.value,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
