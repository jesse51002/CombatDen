"""Handler for Stripe ``invoice.paid`` events."""

import json
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.handlers.stripe_time import (
    stripe_ts_to_date,
    stripe_ts_to_datetime,
)

logger = logging.getLogger(__name__)

EVENT_TYPE = "invoice.paid"
CHARGE_KIND_PAYMENT = "payment"
CHARGE_STATUS_SUCCEEDED = "succeeded"
INVOICE_STATUS_PAID = "paid"


class InvoicePaidHandler:
    """Apply an ``invoice.paid`` event to the CRM database.

    Writes:
      - Upsert ``user_gym_invoices`` row to ``status='paid'``.
      - Update ``member_memberships`` for each billed subscription item
        (``last_paid_date``, ``next_due_date``).
      - Insert a ``user_gym_charges`` row representing the successful
        payment.
    """

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        invoice = event["data"]["object"]
        stripe_invoice_id = invoice.get("id")
        if not stripe_invoice_id:
            raise ValueError("invoice.paid event is missing invoice id")

        crm_user_id = await self._resolve_crm_user_id(session, invoice, gym_id)
        if crm_user_id is None:
            logger.warning(
                "invoice.paid: no membership matched any line item "
                "(stripe_invoice_id=%s, gym_id=%s); skipping",
                stripe_invoice_id,
                gym_id,
            )
            return

        invoice_row = await self._upsert_invoice(
            session,
            invoice,
            gym_id,
            crm_user_id,
        )
        invoice_id: UUID = invoice_row["invoice_id"]

        await self._update_memberships(session, invoice, gym_id)
        await self._insert_payment_charge(
            session,
            invoice,
            gym_id,
            crm_user_id,
            invoice_id,
        )

    # ── Helpers ────────────────────────────────────────────────

    async def _resolve_crm_user_id(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
    ) -> UUID | None:
        """Find a crm_user_id by matching any line's subscription_item.

        An invoice can have multiple lines, all belonging to the same
        customer; we only need one hit to know the crm_user_id.
        """
        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        for line in self._lines(invoice):
            stripe_item_id = line.get("subscription_item")
            if not stripe_item_id:
                continue
            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": stripe_item_id,
                    "gym_id": str(gym_id),
                },
            )
            row = result.mappings().fetchone()
            if row is not None:
                return row["crm_user_id"]
        return None

    async def _upsert_invoice(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        crm_user_id: UUID,
    ) -> dict[str, Any]:
        upsert_sql = load_sql(SQL_DIR / "user_gym_invoice_upsert.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        params = {
            "gym_id": str(gym_id),
            "crm_user_id": str(crm_user_id),
            "status": INVOICE_STATUS_PAID,
            "total_amount": int(invoice.get("amount_paid") or invoice.get("total") or 0),
            "currency": invoice.get("currency", "usd"),
            "stripe_invoice_id": invoice["id"],
            "stripe_payment_intent_id": invoice.get("payment_intent"),
            "invoice_time": stripe_ts_to_datetime(paid_at_ts),
            "stripe_event_payload": json.dumps(invoice),
        }
        result = await session.execute(text(upsert_sql), params)
        row = result.mappings().fetchone()
        if row is None:
            raise RuntimeError(f"Failed to upsert invoice for stripe_invoice_id={invoice['id']}")
        return dict(row)

    async def _update_memberships(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        update_sql = load_sql(SQL_DIR / "member_memberships_update_payment_dates.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        last_paid_date = stripe_ts_to_date(paid_at_ts)

        for line in self._lines(invoice):
            stripe_item_id = line.get("subscription_item")
            if not stripe_item_id:
                continue

            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": stripe_item_id,
                    "gym_id": str(gym_id),
                },
            )
            row = result.mappings().fetchone()
            if row is None:
                logger.warning(
                    "invoice.paid: no membership for stripe_item_id=%s gym_id=%s",
                    stripe_item_id,
                    gym_id,
                )
                continue

            period_end_ts = line.get("period", {}).get("end")
            next_due_date = stripe_ts_to_date(period_end_ts)

            await session.execute(
                text(update_sql),
                {
                    "item_id": str(row["item_id"]),
                    "gym_id": str(gym_id),
                    "last_paid_date": last_paid_date,
                    "next_due_date": next_due_date,
                },
            )

    async def _insert_payment_charge(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        crm_user_id: UUID,
        invoice_id: UUID,
    ) -> None:
        stripe_charge_id = invoice.get("charge")
        amount_paid = int(invoice.get("amount_paid") or 0)

        # Schema requires payment rows to have a stripe_charge_id
        # (unless cash). Skip the charge insert for zero-amount paid
        # invoices with no underlying charge (e.g. 100%-off trials).
        if not stripe_charge_id:
            if amount_paid == 0:
                return
            raise ValueError(
                f"invoice.paid has amount_paid={amount_paid} but no charge id "
                f"(stripe_invoice_id={invoice.get('id')})"
            )

        insert_sql = load_sql(SQL_DIR / "user_gym_charge_insert.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        params = {
            "invoice_id": str(invoice_id),
            "gym_id": str(gym_id),
            "crm_user_id": str(crm_user_id),
            "kind": CHARGE_KIND_PAYMENT,
            "status": CHARGE_STATUS_SUCCEEDED,
            "amount": amount_paid,
            "currency": invoice.get("currency", "usd"),
            "payment_method_type": None,
            "stripe_charge_id": stripe_charge_id,
            "stripe_refund_id": None,
            "refunds_charge_id": None,
            "charge_time": stripe_ts_to_datetime(paid_at_ts),
            "stripe_event_payload": json.dumps(invoice),
        }
        await session.execute(text(insert_sql), params)

    @staticmethod
    def _lines(invoice: dict[str, Any]) -> list[dict[str, Any]]:
        lines = invoice.get("lines") or {}
        return list(lines.get("data") or [])
