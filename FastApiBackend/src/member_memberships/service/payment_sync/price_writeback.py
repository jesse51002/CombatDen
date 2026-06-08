"""Write the paying parent's monthly recurring total back from Stripe.

Stripe is the source of truth for what the parent's account is actually
charged each month (after discounts, consolidation, and quantity). After
any mutation that touches a recurring subscription, this pulls the
upcoming invoice and writes ``members.total_monthly_recurring_price`` on
the paying parent's profile.

Each membership's OWN post-discount price (``member_memberships.total_price``)
is computed at build time by ``PaymentSyncDiscounts`` and written by
``PaymentSyncWriteback`` — not here.
"""

from __future__ import annotations

import logging
from uuid import UUID

from src.member_memberships import SQL_DIR
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_SYNC_PROFILE_TOTAL_SQL_PATH = (
    SQL_DIR / "payment_sync" / "sync_profile_monthly_total.sql"
)


class PriceWriteback:
    """Writes the paying parent's monthly recurring total from Stripe.

    Pulls the parent's Stripe upcoming-invoice preview and sums its
    recurring lines (proration already filtered out by the mapper) onto
    ``members.total_monthly_recurring_price``. Logically independent of the
    sync layer — it only needs the parent and the live subscription. Any
    failure is logged at ERROR but never re-raised: Stripe is authoritative
    and a later mutation or reconciliation sweep re-corrects the mirror.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._db_pool = db_pool
        self._subscription_service = subscription_service

    async def sync_parent_monthly_total(
        self,
        parent_member_id: UUID,
        stripe_sub_id: str | None,
        stripe_account_id: str,
    ) -> None:
        """Set the parent's monthly recurring total from the upcoming invoice.

        When ``stripe_sub_id`` is None the parent's subscription is gone
        (fully cancelled by this operation), so the monthly total is zeroed.
        Must not be called from non-recurring flows (one-time invoices) —
        those have no subscription to preview.

        Args:
            parent_member_id: The paying parent's profile ID.
            stripe_sub_id: The live Stripe subscription ID, or None if the
                parent's subscription no longer exists.
            stripe_account_id: The gym's Stripe Connect account ID.
        """
        if not stripe_sub_id:
            await self._update_parent_monthly_total(parent_member_id, 0)
            return

        try:
            upcoming = await self._subscription_service.fetch_upcoming_invoice(
                stripe_sub_id,
                stripe_account_id,
            )
        except PaymentsResourceNotFoundError:
            logger.error(
                "Upcoming invoice not found for subscription %s; "
                "skipping monthly total writeback",
                stripe_sub_id,
                exc_info=True,
            )
            return
        except Exception:
            logger.error(
                "Failed to fetch upcoming invoice for subscription %s; "
                "skipping monthly total writeback",
                stripe_sub_id,
                exc_info=True,
            )
            return

        # Sum the recurring lines (proration already filtered out by the
        # mapper) so the profile monthly total reflects steady state, not a
        # one-time post-add invoice spike.
        recurring_total = sum(
            max(line.discounted_amount, 0) for line in upcoming.lines
        )
        await self._update_parent_monthly_total(
            parent_member_id,
            recurring_total,
        )

    async def _update_parent_monthly_total(
        self,
        parent_member_id: UUID,
        amount_due: int,
    ) -> None:
        """Set total_monthly_recurring_price on the parent profile."""
        sql = load_sql(_SYNC_PROFILE_TOTAL_SQL_PATH)
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {
                    "member_id": str(parent_member_id),
                    "total_monthly_recurring_price": max(amount_due, 0),
                },
            )
        except Exception:
            logger.error(
                "Failed to update total_monthly_recurring_price on parent %s",
                parent_member_id,
                exc_info=True,
            )
