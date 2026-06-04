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
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsCancel(MemberMembershipsBase):
    """Cancel a specific active recurring membership."""

    async def cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> date:
        """Cancel a specific active recurring membership.

        Syncs the cancellation to Stripe first (including linked
        discount recalculation), then updates the CRM database.

        If the membership is already cancelled, this is a no-op.

        Args:
            item_id: The membership item.
            member_id: The member.
            idempotency_key: Caller-supplied key scoped to this cancel.

        Raises:
            ValueError: If the membership is not found, has already
                ended, or is non-recurring.
        """
        row = await self._get_membership(item_id, member_id)

        if row["cancel_date"] is not None:
            return row["cancel_date"]

        self._validate_cancel(row, item_id, member_id)

        # ── Stripe sync (includes linked discount recalc) ──
        cancel_item = SyncItem(
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            member_id=member_id,
            plan_id=row["plan_id"],
        )
        try:
            await self._payment_sync.update_payments_recurring(
                member_id,
                add_ids=[],
                cancel_ids=[cancel_item],
                idempotency_key=idempotency_key,
            )
        except PaymentsResourceNotFoundError:
            logger.warning(
                "Stripe resource not found during cancel "
                "(proceeding with CRM cancel): "
                "item_id=%s, member_id=%s",
                item_id,
                member_id,
            )

        # ── CRM cancel ────────────────────────────────────
        return await self._crm_cancel(item_id, member_id, gym_today(row["timezone"]))

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what cancelling a membership would charge.

        Runs every validation ``cancel`` runs (membership lookup,
        already-cancelled short-circuit, recurring-plan guard) and
        then calls the Stripe invoice preview. Returns ``None`` if
        the membership is already cancelled or if cancellation
        would drop the subscription to zero items (pure
        cancellations have no upcoming invoice).

        Raises:
            ValueError: Same conditions as ``cancel``.
        """
        row = await self._get_membership(item_id, member_id)

        if row["cancel_date"] is not None:
            return None

        self._validate_cancel(row, item_id, member_id)

        cancel_item = SyncItem(
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            member_id=member_id,
            plan_id=row["plan_id"],
        )
        return await self._payment_sync.preview_update_payments_recurring(
            member_id,
            add_ids=[],
            cancel_ids=[cancel_item],
        )

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _validate_cancel(
        row: dict,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate a membership can be cancelled."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Cannot cancel non-recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"item_id={item_id}, member_id={member_id}"
            )

        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            logger.warning(
                f"Recurring membership has ended set. "
                f"Shouldn't be possible "
                f"(end_date={row['end_date']}): "
                f"item_id={item_id}, member_id={member_id}"
            )

    async def _crm_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> date:
        """Mark membership as cancelled in the CRM database.

        Returns the resolved ``cancel_date`` (the date through which
        the membership remains active).
        """
        cancel_sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
            "gym_today": today,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(cancel_sql), params)
            cancel_date = result.scalar_one()
            await session.commit()
        return cancel_date
