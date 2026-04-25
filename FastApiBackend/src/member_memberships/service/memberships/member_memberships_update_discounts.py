"""Replace the discount set on an existing membership."""

import json
import logging
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MemberMembershipsUpdateDiscounts(MemberMembershipsBase):
    """Replace the discount_ids set on a live recurring membership."""

    async def update_discounts(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        discount_ids: list[UUID],
        idempotency_key: UUID,
    ) -> None:
        """Replace the discount_ids array on an existing membership.

        Writes the new discount set to the CRM row first, then
        re-syncs the Stripe subscription so the matching item's
        coupon list reflects the change. No mid-cycle invoice is
        cut — the next renewal is the first cycle to bill the new
        discounted total.

        ``discount_ids`` is the full desired set — an empty list
        detaches every discount currently on the membership.

        Args:
            item_id: The membership item.
            crm_user_id: The member.
            discount_ids: Full replacement discount set.

        Raises:
            ValueError: If membership not found, cancelled, ended,
                missing Stripe linkage, or any discount_id is
                unknown / belongs to a different gym.
        """
        row = await self._get_membership(item_id, crm_user_id)
        self._validate_update_discounts(row, item_id, crm_user_id)
        await self._validate_discount_ids(row["gym_id"], discount_ids)

        await self._crm_update_discounts(
            item_id=item_id,
            crm_user_id=crm_user_id,
            discount_ids=discount_ids,
        )

        await self._payment_sync.update_payments_recurring(
            crm_user_id,
            add_ids=[],
            cancel_ids=[],
            idempotency_key=idempotency_key,
        )

    async def preview_update_discounts(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        discount_ids: list[UUID],
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what replacing the discount set would charge.

        Runs every validation ``update_discounts`` runs and then
        asks the payment-sync preview path to build the Stripe
        invoice preview with the proposed ``discount_ids`` applied
        in-memory — no CRM rows are written.

        Raises:
            ValueError: Same conditions as ``update_discounts``.
        """
        row = await self._get_membership(item_id, crm_user_id)
        self._validate_update_discounts(row, item_id, crm_user_id)
        await self._validate_discount_ids(row["gym_id"], discount_ids)

        return await self._payment_sync.preview_update_payments_recurring(
            crm_user_id,
            add_ids=[],
            cancel_ids=[],
            override_plan_id=row["plan_id"],
            override_discount_ids=discount_ids,
        )

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _validate_update_discounts(
        row: dict,
        item_id: UUID,
        crm_user_id: UUID,
    ) -> None:
        """Validate a membership can have its discount set updated."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot update discounts on cancelled membership: "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            raise ValueError(
                f"Cannot update discounts on ended membership: "
                f"item_id={item_id}, crm_user_id={crm_user_id}"
            )
        if not row["stripe_item_id"]:
            raise ValueError(f"Membership missing stripe_item_id for item_id={item_id}")

    async def _validate_discount_ids(
        self,
        gym_id: UUID,
        discount_ids: list[UUID],
    ) -> None:
        """Ensure every submitted id exists and belongs to this gym.

        The DB trigger ``trg_check_discount_ids_gym_match`` also
        enforces gym ownership on the INSERT/UPDATE path, but
        validating up front lets us raise a clean ``ValueError``
        with an explicit missing-id list instead of a Postgres
        constraint error.

        Raises:
            ValueError: If any id is unknown or cross-gym.
        """
        if not discount_ids:
            return

        sql = load_sql(SQL_DIR / "member_memberships_get_discounts.sql")
        params = {
            "gym_id": str(gym_id),
            "discount_ids": [str(d) for d in discount_ids],
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = result.mappings().fetchall()

        found = {row["discount_id"] for row in rows}
        missing = [d for d in discount_ids if d not in found]
        if missing:
            raise ValueError(
                f"Discounts not found for gym_id={gym_id}: {[str(d) for d in missing]}"
            )

    async def _crm_update_discounts(
        self,
        item_id: UUID,
        crm_user_id: UUID,
        discount_ids: list[UUID],
    ) -> None:
        """Replace the JSONB discount_ids array on a membership."""
        sql = load_sql(SQL_DIR / "member_memberships_update_discounts.sql")
        payload = json.dumps([str(d) for d in discount_ids]) if discount_ids else "[]"
        params = {
            "item_id": str(item_id),
            "crm_user_id": str(crm_user_id),
            "discount_ids": payload,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()
