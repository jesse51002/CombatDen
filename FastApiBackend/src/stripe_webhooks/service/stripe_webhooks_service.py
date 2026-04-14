"""Dispatcher for Stripe webhook events."""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.handlers.charge_refunded_handler import (
    ChargeRefundedHandler,
)
from src.stripe_webhooks.service.handlers.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.handlers.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)

logger = logging.getLogger(__name__)

EVENT_INVOICE_PAID = "invoice.paid"
EVENT_INVOICE_PAYMENT_FAILED = "invoice.payment_failed"
EVENT_CHARGE_REFUNDED = "charge.refunded"


class StripeWebhooksService:
    """Resolve gym, deduplicate, and dispatch to event handlers.

    All database work for a single event runs inside one transaction
    opened by this dispatcher. The event-log insert and the handler
    writes commit or roll back together, so a Stripe retry after a
    handler failure re-runs the whole thing cleanly.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        event_log: StripeWebhookEventLog,
        invoice_paid_handler: InvoicePaidHandler,
        invoice_payment_failed_handler: InvoicePaymentFailedHandler,
        charge_refunded_handler: ChargeRefundedHandler,
    ) -> None:
        self._db_pool = db_pool
        self._event_log = event_log
        self._invoice_paid = invoice_paid_handler
        self._invoice_payment_failed = invoice_payment_failed_handler
        self._charge_refunded = charge_refunded_handler

    async def handle_event(self, event: dict[str, Any]) -> None:
        """Dispatch a verified Stripe event.

        Raises on unexpected errors so the caller can return 5xx and
        Stripe will retry. Unknown event types are logged and ignored.
        """
        event_id = event.get("id")
        event_type = event.get("type")
        stripe_account_id = event.get("account")

        if not event_id or not event_type:
            raise ValueError("Stripe event missing id or type")

        if not stripe_account_id:
            logger.info(
                "Received platform-level event on Connect webhook endpoint: "
                "event_id=%s event_type=%s; ignoring",
                event_id,
                event_type,
            )
            return

        gym_id = await self._resolve_gym(stripe_account_id)
        if gym_id is None:
            logger.warning(
                "Received Stripe event for unknown connected account: "
                "event_id=%s event_type=%s stripe_account_id=%s; ignoring",
                event_id,
                event_type,
                stripe_account_id,
            )
            return

        async with self._db_pool.session() as session, session.begin():
            is_new = await self._event_log.record(
                session,
                event_id=event_id,
                gym_id=gym_id,
                event_type=event_type,
            )
            if not is_new:
                return

            await self._dispatch(session, event, event_type, gym_id)

    # ── Internals ──────────────────────────────────────────────

    async def _resolve_gym(self, stripe_account_id: str) -> UUID | None:
        lookup_sql = load_sql(SQL_DIR / "gym_by_stripe_account.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(lookup_sql),
                {"stripe_account_id": stripe_account_id},
            )
            row = result.mappings().fetchone()
        if row is None:
            return None
        return row["gym_id"]

    async def _dispatch(
        self,
        session: Any,
        event: dict[str, Any],
        event_type: str,
        gym_id: UUID,
    ) -> None:
        if event_type == EVENT_INVOICE_PAID:
            await self._invoice_paid.handle(session, event, gym_id)
        elif event_type == EVENT_INVOICE_PAYMENT_FAILED:
            await self._invoice_payment_failed.handle(session, event, gym_id)
        elif event_type == EVENT_CHARGE_REFUNDED:
            await self._charge_refunded.handle(session, event, gym_id)
        else:
            logger.info(
                "Unhandled Stripe event type: %s (event_id=%s, gym_id=%s)",
                event_type,
                event.get("id"),
                gym_id,
            )
