"""Fan post-discount Stripe prices back onto CRM membership rows.

Stripe is the source of truth for what a member is actually charged
(after discounts, consolidation, and quantity). After any mutation
that touches a recurring subscription, this orchestrator pulls the
upcoming invoice and writes:

* ``member_memberships_unfiltered.total_price`` — the per-unit
  post-discount amount on every row sharing a ``stripe_item_id``.
* ``user_gym_profiles_unfiltered.total_monthly_recurring_price`` —
  the full monthly recurring charge on the paying parent's profile.
"""

from __future__ import annotations

import logging
from uuid import UUID

from src.member_memberships import SQL_DIR
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_invoice_schema import UpcomingInvoiceLine
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_SYNC_PRICES_SQL_PATH = SQL_DIR / "payment_sync" / "sync_prices_by_stripe_item.sql"
_SYNC_PROFILE_TOTAL_SQL_PATH = SQL_DIR / "payment_sync" / "sync_profile_monthly_total.sql"


class PriceWriteback:
    """Writeback helper called from every membership mutation flow.

    Uses the Stripe upcoming-invoice preview to get post-discount
    per-unit amounts, then fans them out across all CRM rows sharing
    the same ``stripe_item_id`` and updates the parent profile's
    monthly total.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._db_pool = db_pool
        self._subscription_service = subscription_service

    async def sync_prices_from_stripe(
        self,
        parent_crm_user_id: UUID,
        stripe_sub_id: str | None,
        stripe_account_id: str,
    ) -> None:
        """Sync total_price + profile monthly total from Stripe.

        Callers should invoke this after any recurring-subscription
        mutation. When ``stripe_sub_id`` is None the parent's
        subscription is gone (fully cancelled by this operation), so
        the profile's monthly total is zeroed. Any failures during
        the writeback are logged at ERROR but never re-raised —
        Stripe is authoritative and a later mutation or reconciliation
        sweep will re-correct the CRM mirror.

        This must not be called from non-recurring flows (one-time
        invoices) — those have no subscription to preview.

        Args:
            parent_crm_user_id: The paying parent's profile ID.
            stripe_sub_id: The live Stripe subscription ID, or None
                if the parent's subscription no longer exists.
            stripe_account_id: The gym's Stripe Connect account ID.
        """
        if not stripe_sub_id:
            await self._update_parent_monthly_total(parent_crm_user_id, 0)
            return

        try:
            upcoming = await self._subscription_service.fetch_upcoming_invoice(
                stripe_sub_id,
                stripe_account_id,
            )
        except PaymentsResourceNotFoundError:
            logger.error(
                "Upcoming invoice not found for subscription %s; skipping price writeback",
                stripe_sub_id,
                exc_info=True,
            )
            return
        except Exception:
            logger.error(
                "Failed to fetch upcoming invoice for subscription %s; skipping price writeback",
                stripe_sub_id,
                exc_info=True,
            )
            return

        await self._fan_out_line_prices(upcoming.lines)
        await self._update_parent_monthly_total(
            parent_crm_user_id,
            upcoming.amount_due,
        )

    async def _fan_out_line_prices(
        self,
        lines: list[UpcomingInvoiceLine],
    ) -> None:
        """Write per-unit post-discount amounts across sibling rows."""
        sql = load_sql(_SYNC_PRICES_SQL_PATH)
        for line in lines:
            unit_amount = line.amount if line.amount > 0 else 0
            try:
                await self._db_pool.execute_with_retry(
                    sql,
                    {
                        "stripe_item_id": line.stripe_subscription_item_id,
                        "total_price": unit_amount,
                    },
                )
            except Exception:
                logger.error(
                    "Failed to fan out total_price for stripe_item_id %s",
                    line.stripe_subscription_item_id,
                    exc_info=True,
                )

    async def _update_parent_monthly_total(
        self,
        parent_crm_user_id: UUID,
        amount_due: int,
    ) -> None:
        """Set total_monthly_recurring_price on the parent profile."""
        sql = load_sql(_SYNC_PROFILE_TOTAL_SQL_PATH)
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {
                    "crm_user_id": str(parent_crm_user_id),
                    "total_monthly_recurring_price": max(amount_due, 0),
                },
            )
        except Exception:
            logger.error(
                "Failed to update total_monthly_recurring_price on parent %s",
                parent_crm_user_id,
                exc_info=True,
            )
