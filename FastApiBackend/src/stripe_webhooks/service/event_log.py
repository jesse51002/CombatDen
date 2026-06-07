"""Idempotency log for Stripe webhook events."""

import logging
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR

logger = logging.getLogger(__name__)


class StripeWebhookEventLog:
    """Inserts webhook events into stripe_webhook_events for idempotency.

    The insert uses ON CONFLICT DO NOTHING so duplicate deliveries
    return None and the caller can skip handler execution.
    """

    async def record(
        self,
        session: AsyncSession,
        event_id: str,
        gym_id: UUID,
        event_type: str,
    ) -> bool:
        """Record a webhook event.

        Returns:
            True if this is the first time we see the event (handler
            should run), False if the event was already processed.
        """
        insert_sql = load_sql(SQL_DIR / "stripe_webhook_events_insert.sql")
        params = {
            "event_id": event_id,
            "gym_id": str(gym_id),
            "event_type": event_type,
        }
        result = await session.execute(text(insert_sql), params)
        row = result.mappings().fetchone()
        if row is None:
            logger.info(
                "Duplicate Stripe webhook event skipped: event_id=%s",
                event_id,
            )
            return False
        return True
