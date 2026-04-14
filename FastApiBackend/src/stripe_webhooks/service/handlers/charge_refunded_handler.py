"""Handler for Stripe ``charge.refunded`` events."""

import json
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.handlers.stripe_time import stripe_ts_to_datetime

logger = logging.getLogger(__name__)

EVENT_TYPE = "charge.refunded"
CHARGE_KIND_REFUND = "refund"
CHARGE_STATUS_SUCCEEDED = "succeeded"


class ChargeRefundedHandler:
    """Record one or more refunds against a previously-recorded payment.

    Refunds are stored as rows in ``user_gym_charges`` with
    ``kind='refund'`` and a negative amount, linked to the original
    payment row via ``refunds_charge_id``.
    """

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        charge = event["data"]["object"]
        stripe_charge_id = charge.get("id")
        if not stripe_charge_id:
            raise ValueError("charge.refunded event is missing charge id")

        parent = await self._find_parent_charge(
            session,
            stripe_charge_id,
            gym_id,
        )
        if parent is None:
            # We never recorded the original payment — can't create a
            # refund row because invoice_id is NOT NULL. Log and ack;
            # this needs manual reconciliation, not Stripe retries.
            logger.error(
                "charge.refunded: no parent payment row found "
                "(stripe_charge_id=%s, gym_id=%s); cannot record refund",
                stripe_charge_id,
                gym_id,
            )
            return

        refunds = self._refunds(charge)
        if not refunds:
            logger.warning(
                "charge.refunded: event has no refunds.data (stripe_charge_id=%s)",
                stripe_charge_id,
            )
            return

        insert_sql = load_sql(SQL_DIR / "user_gym_charge_insert.sql")
        for refund in refunds:
            stripe_refund_id = refund.get("id")
            if not stripe_refund_id:
                continue
            params = {
                "invoice_id": str(parent["invoice_id"]),
                "gym_id": str(gym_id),
                "crm_user_id": str(parent["crm_user_id"]),
                "kind": CHARGE_KIND_REFUND,
                "status": CHARGE_STATUS_SUCCEEDED,
                "amount": -int(refund.get("amount") or 0),
                "currency": refund.get("currency") or charge.get("currency", "usd"),
                "payment_method_type": None,
                "stripe_charge_id": None,
                "stripe_refund_id": stripe_refund_id,
                "refunds_charge_id": str(parent["charge_id"]),
                "charge_time": stripe_ts_to_datetime(refund.get("created")),
                "stripe_event_payload": json.dumps(charge),
            }
            await session.execute(text(insert_sql), params)

    # ── Helpers ────────────────────────────────────────────────

    async def _find_parent_charge(
        self,
        session: AsyncSession,
        stripe_charge_id: str,
        gym_id: UUID,
    ) -> dict[str, Any] | None:
        lookup_sql = load_sql(SQL_DIR / "user_gym_charge_by_stripe_charge_id.sql")
        result = await session.execute(
            text(lookup_sql),
            {
                "stripe_charge_id": stripe_charge_id,
                "gym_id": str(gym_id),
            },
        )
        row = result.mappings().fetchone()
        return dict(row) if row else None

    @staticmethod
    def _refunds(charge: dict[str, Any]) -> list[dict[str, Any]]:
        refunds = charge.get("refunds") or {}
        return list(refunds.get("data") or [])
