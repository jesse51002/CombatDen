"""Handler for Stripe ``invoice.payment_failed`` events."""

import logging
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_invoice_fields import (
    line_subscription_item,
)
from src.stripe_webhooks.service.stripe_json import dump_stripe_payload
from src.stripe_webhooks.service.stripe_time import stripe_ts_to_datetime
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)

logger = logging.getLogger(__name__)

EVENT_TYPE = "invoice.payment_failed"
CHARGE_KIND_PAYMENT = "payment"
CHARGE_STATUS_FAILED = "failed"
INVOICE_STATUS_OPEN = "open"
# A failed attempt has no real Stripe charge id on the invoice payload, so we
# store a deterministic SYNTHETIC key in stripe_charge_id keyed on the invoice +
# its attempt number. This gives "one row per distinct attempt": the SAME attempt
# seen twice (a webhook re-delivery OR the reconciler invoice fetcher re-listing
# the same invoice) collides on the UNIQUE constraint and dedupes; a NEW attempt
# (Stripe increments attempt_count) gets its own row. It never collides with a
# real ``ch_...`` id (e.g. the later succeeded payment for the same invoice).
FAILED_CHARGE_KEY_PREFIX = "failed_attempt"


class InvoicePaymentFailedHandler:
    """Record a failed renewal payment attempt.

    The CRM surfaces failures by querying
    ``member_charges WHERE status='failed'`` — nothing is mutated on
    the membership row itself. Stripe handles dunning / retry; we do
    not auto-cancel.
    """

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        await self.absorb(session, event["data"]["object"], gym_id)

    async def absorb(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        """Record a failed payment attempt (invoice object) as a charge.

        The seam shared by the webhook dispatcher (``handle`` unwraps the event)
        and the reconciler invoice fetcher (passes the listed invoice directly).
        """
        stripe_invoice_id = invoice.get("id")
        if not stripe_invoice_id:
            raise ValueError("invoice.payment_failed event is missing invoice id")

        member_id = await self._resolve_member_id(session, invoice, gym_id)
        if member_id is None:
            subscription_item_ids = [
                item_id
                for line in self._lines(invoice)
                if (item_id := line_subscription_item(line))
            ]
            if subscription_item_ids:
                raise SubscriptionItemPendingError(
                    stripe_invoice_id=stripe_invoice_id,
                    gym_id=str(gym_id),
                    subscription_item_ids=subscription_item_ids,
                )
            return

        invoice_row = await self._upsert_invoice(
            session,
            invoice,
            gym_id,
            member_id,
        )
        await self._insert_failed_charge(
            session,
            invoice,
            gym_id,
            member_id,
            invoice_row["invoice_id"],
        )

    # ── Helpers ────────────────────────────────────────────────

    async def _resolve_member_id(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
    ) -> UUID | None:
        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        for line in self._lines(invoice):
            stripe_item_id = line_subscription_item(line)
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
                return row["member_id"]
        return None

    async def _upsert_invoice(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        member_id: UUID,
    ) -> dict[str, Any]:
        upsert_sql = load_sql(SQL_DIR / "member_invoice_upsert.sql")
        created_ts = invoice.get("created")
        params = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "status": INVOICE_STATUS_OPEN,
            "total_amount": int(invoice.get("amount_due") or invoice.get("total") or 0),
            "currency": invoice.get("currency", "usd"),
            "stripe_invoice_id": invoice["id"],
            "stripe_payment_intent_id": invoice.get("payment_intent"),
            "invoice_time": stripe_ts_to_datetime(created_ts),
            "stripe_event_payload": dump_stripe_payload(invoice),
        }
        result = await session.execute(text(upsert_sql), params)
        row = result.mappings().fetchone()
        if row is None:
            raise RuntimeError(f"Failed to upsert invoice for stripe_invoice_id={invoice['id']}")
        return dict(row)

    async def _insert_failed_charge(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        member_id: UUID,
        invoice_id: UUID,
    ) -> None:
        # Deterministic synthetic charge id (see FAILED_CHARGE_KEY_PREFIX):
        # ``failed_attempt:<invoice_id>:<attempt_count>`` so the same attempt
        # dedupes (webhook re-delivery or fetcher re-list) while a new attempt
        # gets its own row. ``ON CONFLICT DO NOTHING`` makes the insert idempotent
        # without relying on the event-log (which the fetcher does not use).
        attempt_count = int(invoice.get("attempt_count") or 0)
        synthetic_charge_id = (
            f"{FAILED_CHARGE_KEY_PREFIX}:{invoice['id']}:{attempt_count}"
        )
        insert_sql = load_sql(SQL_DIR / "member_charge_insert.sql")
        params = {
            "invoice_id": str(invoice_id),
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "kind": CHARGE_KIND_PAYMENT,
            "status": CHARGE_STATUS_FAILED,
            "amount": int(invoice.get("amount_due") or 0),
            "currency": invoice.get("currency", "usd"),
            # A failed attempt carries no charge on the invoice payload, so
            # the method type / card last 4 aren't available here.
            "payment_method_type": None,
            "card_last_four": None,
            "stripe_charge_id": synthetic_charge_id,
            "stripe_refund_id": None,
            "refunds_charge_id": None,
            "charge_time": datetime.now(tz=UTC),
            "stripe_event_payload": dump_stripe_payload(invoice),
        }
        await session.execute(text(insert_sql), params)

    @staticmethod
    def _lines(invoice: dict[str, Any]) -> list[dict[str, Any]]:
        lines = invoice.get("lines") or {}
        return list(lines.get("data") or [])
