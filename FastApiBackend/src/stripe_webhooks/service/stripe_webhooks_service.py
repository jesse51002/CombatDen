"""Dispatcher for Stripe webhook events."""

import asyncio
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.account_updated_handler import (
    AccountUpdatedHandler,
)
from src.stripe_webhooks.service.charge_refunded_handler import (
    ChargeRefundedHandler,
)
from src.stripe_webhooks.service.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)

logger = logging.getLogger(__name__)

EVENT_INVOICE_PAID = "invoice.paid"
EVENT_INVOICE_PAYMENT_FAILED = "invoice.payment_failed"
EVENT_CHARGE_REFUNDED = "charge.refunded"
EVENT_ACCOUNT_UPDATED = "account.updated"


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
        account_updated_handler: AccountUpdatedHandler,
    ) -> None:
        self._db_pool = db_pool
        self._event_log = event_log
        self._invoice_paid = invoice_paid_handler
        self._invoice_payment_failed = invoice_payment_failed_handler
        self._charge_refunded = charge_refunded_handler
        self._account_updated = account_updated_handler

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

    async def retry_pending_event(
        self,
        event: dict[str, Any],
        max_attempts: int = 3,
        delay: float = 10.0,
    ) -> None:
        """Retry processing a webhook event whose subscription item was not yet visible.

        Called as a background task after the router returns 200 to Stripe.
        Retries ``handle_event`` up to *max_attempts* times with *delay*
        seconds between each attempt.  On success the event is logged in the
        idempotency table normally.  If all retries are exhausted the Stripe
        write genuinely failed and we log an error.
        """
        event_id = event.get("id")
        for attempt in range(1, max_attempts + 1):
            await asyncio.sleep(delay)
            try:
                await self.handle_event(event)
                logger.info(
                    "Background retry succeeded on attempt %d/%d: event_id=%s",
                    attempt,
                    max_attempts,
                    event_id,
                )
                return
            except SubscriptionItemPendingError:
                logger.info(
                    "Background retry %d/%d still pending: event_id=%s",
                    attempt,
                    max_attempts,
                    event_id,
                )
        logger.error(
            "Background retry exhausted after %d attempts: event_id=%s. "
            "Subscription item was never written — possible StripeOrphanError "
            "or create-flow failure.",
            max_attempts,
            event_id,
        )

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
        elif event_type == EVENT_ACCOUNT_UPDATED:
            await self._account_updated.handle(session, event, gym_id)
        else:
            return
