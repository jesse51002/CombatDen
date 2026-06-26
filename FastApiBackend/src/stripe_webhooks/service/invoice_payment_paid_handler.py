"""Handler for Stripe ``invoice_payment.paid`` events (one per payment, partial or full)."""

from __future__ import annotations

import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_json import dump_stripe_payload
from src.stripe_webhooks.service.stripe_time import stripe_ts_to_datetime
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    InvoiceNotYetRecordedError,
)

logger = logging.getLogger(__name__)

# (charge_id, payment_method_type, card_last_four) resolved from Stripe.
ChargeDetails = tuple[str | None, str | None, str | None]

EVENT_TYPE = "invoice_payment.paid"
CHARGE_KIND_PAYMENT = "payment"
CHARGE_STATUS_SUCCEEDED = "succeeded"
PAYMENT_METHOD_TYPE_CASH = "cash"
# InvoicePayment.payment.type discriminators we handle.
PAYMENT_TYPE_PAYMENT_INTENT = "payment_intent"
PAYMENT_TYPE_OUT_OF_BAND = "out_of_band"
PAYMENT_STATUS_PAID = "paid"


class InvoicePaymentPaidHandler:
    """Insert a ``member_charges`` payment row for each ``invoice_payment.paid`` event."""

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        await self.record(
            session,
            event["data"]["object"],
            gym_id,
            stripe_account_id=event.get("account"),
        )

    async def record(
        self,
        session: AsyncSession,
        invoice_payment: dict[str, Any],
        gym_id: UUID,
        *,
        stripe_account_id: str | None = None,
        charge_details: ChargeDetails | None = None,
    ) -> None:
        """Record a succeeded InvoicePayment as a charge row. Idempotent via stripe_charge_id."""
        if invoice_payment.get("status") != PAYMENT_STATUS_PAID:
            return

        stripe_invoice_id = invoice_payment.get("invoice")
        if not stripe_invoice_id:
            raise ValueError(
                "invoice_payment.paid event is missing invoice id"
            )

        invoice_row = await self._lookup_invoice(
            session, stripe_invoice_id, gym_id
        )
        if invoice_row is None:
            # invoice.paid hasn't landed yet — retry (member_charges FKs member_invoices).
            raise InvoiceNotYetRecordedError(
                stripe_invoice_id=stripe_invoice_id,
                gym_id=str(gym_id),
            )

        if charge_details is None:
            charge_details = await self._resolve_charge(
                invoice_payment, stripe_account_id
            )
        charge_id, payment_method_type, card_last_four = charge_details

        amount_paid = int(invoice_payment.get("amount_paid") or 0)
        if charge_id is None and payment_method_type != PAYMENT_METHOD_TYPE_CASH:
            # Unhandled payment type with no charge id — skip.
            logger.warning(
                "invoice_payment.paid: no charge id resolved "
                "(stripe_invoice_id=%s gym_id=%s payment_type=%s) — skipping",
                stripe_invoice_id,
                gym_id,
                (invoice_payment.get("payment") or {}).get("type"),
            )
            return

        await self._insert_charge(
            session,
            invoice_payment=invoice_payment,
            gym_id=gym_id,
            paid_by_member_id=invoice_row["paid_by_member_id"],
            invoice_id=invoice_row["invoice_id"],
            amount=amount_paid,
            stripe_charge_id=charge_id,
            payment_method_type=payment_method_type,
            card_last_four=card_last_four,
        )

    async def _lookup_invoice(
        self,
        session: AsyncSession,
        stripe_invoice_id: str,
        gym_id: UUID,
    ) -> dict[str, Any] | None:
        lookup_sql = load_sql(SQL_DIR / "member_invoice_by_stripe_id.sql")
        result = await session.execute(
            text(lookup_sql),
            {
                "stripe_invoice_id": stripe_invoice_id,
                "gym_id": str(gym_id),
            },
        )
        row = result.mappings().fetchone()
        return dict(row) if row is not None else None

    async def resolve_charge(
        self,
        invoice_payment: dict[str, Any],
        stripe_account_id: str | None,
    ) -> ChargeDetails:
        """Resolve charge details from Stripe with no DB I/O."""
        return await self._resolve_charge(invoice_payment, stripe_account_id)

    async def _resolve_charge(
        self,
        invoice_payment: dict[str, Any],
        stripe_account_id: str | None,
    ) -> ChargeDetails:
        """Return (charge_id, payment_method_type, card_last_four) from the payment."""
        payment = invoice_payment.get("payment") or {}
        payment_type = payment.get("type")

        if payment_type == PAYMENT_TYPE_OUT_OF_BAND:
            return None, PAYMENT_METHOD_TYPE_CASH, None

        if payment_type == PAYMENT_TYPE_PAYMENT_INTENT:
            payment_intent_id = payment.get("payment_intent")
            if not payment_intent_id or not stripe_account_id:
                return None, None, None
            opts = PaymentsStripeClient.connect_opts_readonly(stripe_account_id)
            intent = await self._stripe.v1.payment_intents.retrieve_async(
                payment_intent_id,
                params={"expand": ["latest_charge"]},
                options=opts,
            )
            return self._read_charge_details(
                getattr(intent, "latest_charge", None)
            )

        return None, None, None

    @staticmethod
    def _attr(obj: Any, key: str) -> Any:
        """Read ``key`` off a Stripe object or a plain dict (or None)."""
        if obj is None:
            return None
        if isinstance(obj, dict):
            return obj.get(key)
        return getattr(obj, key, None)

    def _read_charge_details(
        self,
        charge: Any,
    ) -> tuple[str | None, str | None, str | None]:
        """Extract (charge_id, payment_method_type, card_last_four) from an expanded charge."""
        if charge is None:
            return None, None, None
        if isinstance(charge, str):
            return charge, None, None
        charge_id = self._attr(charge, "id")
        details = self._attr(charge, "payment_method_details")
        method_type = self._attr(details, "type")
        card_last_four = None
        if method_type == "card":
            card_last_four = self._attr(self._attr(details, "card"), "last4")
        return charge_id, method_type, card_last_four

    async def _insert_charge(
        self,
        session: AsyncSession,
        *,
        invoice_payment: dict[str, Any],
        gym_id: UUID,
        paid_by_member_id: UUID,
        invoice_id: UUID,
        amount: int,
        stripe_charge_id: str | None,
        payment_method_type: str | None,
        card_last_four: str | None,
    ) -> None:
        insert_sql = load_sql(SQL_DIR / "member_charge_insert.sql")
        paid_at_ts = (
            invoice_payment.get("status_transitions", {}).get("paid_at")
            or invoice_payment.get("created")
        )
        await session.execute(
            text(insert_sql),
            {
                "invoice_id": str(invoice_id),
                "gym_id": str(gym_id),
                "paid_by_member_id": str(paid_by_member_id),
                "kind": CHARGE_KIND_PAYMENT,
                "status": CHARGE_STATUS_SUCCEEDED,
                "amount": amount,
                "currency": invoice_payment.get("currency", "usd"),
                "payment_method_type": payment_method_type,
                "card_last_four": card_last_four,
                "stripe_charge_id": stripe_charge_id,
                "stripe_refund_id": None,
                "refunds_charge_id": None,
                "charge_time": stripe_ts_to_datetime(paid_at_ts),
                "stripe_event_payload": dump_stripe_payload(invoice_payment),
            },
        )
