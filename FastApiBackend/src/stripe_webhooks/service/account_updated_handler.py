"""Handler for Stripe ``account.updated`` events.

Connect fires ``account.updated`` whenever a connected Express
account's state changes — onboarding progress, disabled_reason
flips, payouts being enabled, etc.  The handler projects the
Stripe Account dict into the canonical
``gyms.stripe_onboarding_status`` value and writes it to ``gyms``.

Dedupe via ``stripe_webhook_events`` is handled by the outer
dispatcher — this handler participates in the same transaction.
"""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.gyms.service.gyms_status_mapping import map_account_to_snapshot
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR

logger = logging.getLogger(__name__)

EVENT_TYPE = "account.updated"


class AccountUpdatedHandler:
    """Sync a connected account's onboarding status into ``gyms``."""

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        account = event["data"]["object"]
        if not isinstance(account, dict):
            raise ValueError(
                "account.updated event payload is not a dict",
            )

        snapshot = map_account_to_snapshot(account)

        sql = load_sql(SQL_DIR / "gyms_set_onboarding_status.sql")
        await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "status": snapshot.status,
            },
        )

        logger.info(
            "account.updated: gym_id=%s stripe_account_id=%s status=%s "
            "details_submitted=%s charges_enabled=%s payouts_enabled=%s "
            "disabled_reason=%s",
            gym_id,
            account.get("id"),
            snapshot.status,
            snapshot.details_submitted,
            snapshot.charges_enabled,
            snapshot.payouts_enabled,
            snapshot.disabled_reason,
        )
