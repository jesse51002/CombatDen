"""Fan post-discount Stripe totals back onto CRM membership rows.

Stripe is the source of truth for what a member is actually charged
(after discounts, consolidation, and quantity). After any mutation
that touches a recurring subscription, this orchestrator pulls the
upcoming invoice and writes:

* ``member_memberships_unfiltered.total_price`` — the plan-level
  post-discount total, scoped to the paying parent's family. Every
  row in the family sharing a ``plan_id`` ends up with the same
  summed amount (covers the multi-price-tier case where one plan
  spans multiple Stripe subscription items).
* ``user_gym_profiles_unfiltered.total_monthly_recurring_price`` —
  the full monthly recurring charge on the paying parent's profile.
"""

from __future__ import annotations

import json
import logging
from uuid import UUID

from sqlalchemy import text

from src.member_memberships import SQL_DIR
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_invoice_schema import UpcomingInvoiceLine
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_SYNC_PRICES_BY_PLAN_SQL_PATH = SQL_DIR / "payment_sync" / "sync_prices_by_plan.sql"
_SYNC_PROFILE_TOTAL_SQL_PATH = SQL_DIR / "payment_sync" / "sync_profile_monthly_total.sql"
_GET_FAMILY_IDS_SQL_PATH = SQL_DIR / "payment_sync" / "get_family_ids.sql"


class PriceWriteback:
    """Writeback helper called from every membership mutation flow.

    Uses the Stripe upcoming-invoice preview to get post-discount
    line totals, groups them by ``plan_id`` (via
    ``membership_plan_prices``), and fans the per-plan sum across
    every member_memberships row in the paying parent's family on
    that plan. Also updates the parent profile's monthly total.

    The writeback is logically independent of the sync layer — it
    only needs the parent (for family + profile scoping) and the
    Stripe subscription to do its job. Because writes are DB-first,
    any row just inserted by a caller is already present with its
    ``plan_id`` set by the time the writeback runs, so remove/add
    flows don't need a return value.
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
        gym_id: UUID,
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
            gym_id: The gym the family belongs to. Used to scope the
                family-ids lookup so linked children are resolved
                correctly.
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

        family_ids = await self._fetch_family_ids(parent_crm_user_id, gym_id)
        if family_ids:
            await self._update_plan_totals(family_ids, upcoming.lines)
        else:
            logger.error(
                "No family ids resolved for parent %s in gym %s; skipping plan writeback",
                parent_crm_user_id,
                gym_id,
            )

        # Sum the recurring lines (proration already filtered out by
        # the mapper) so the profile monthly total reflects steady
        # state, not a one-time post-add invoice spike.
        recurring_total = sum(max(line.amount, 0) for line in upcoming.lines)
        await self._update_parent_monthly_total(
            parent_crm_user_id,
            recurring_total,
        )

    async def _fetch_family_ids(
        self,
        parent_crm_user_id: UUID,
        gym_id: UUID,
    ) -> list[UUID]:
        """Resolve parent + linked children crm_user_ids."""
        sql = load_sql(_GET_FAMILY_IDS_SQL_PATH)
        try:
            async with self._db_pool.session() as session:
                result = await session.execute(
                    text(sql),
                    {
                        "parent_crm_user_id": str(parent_crm_user_id),
                        "gym_id": str(gym_id),
                    },
                )
                rows = result.mappings().fetchall()
            return [UUID(str(r["crm_user_id"])) for r in rows]
        except Exception:
            logger.error(
                "Failed to fetch family ids for parent %s in gym %s",
                parent_crm_user_id,
                gym_id,
                exc_info=True,
            )
            return []

    async def _update_plan_totals(
        self,
        family_ids: list[UUID],
        lines: list[UpcomingInvoiceLine],
    ) -> None:
        """Write plan-level post-discount totals across family rows."""
        payload = [
            {
                "stripe_price_id": line.stripe_price_id,
                "amount": max(line.amount, 0),
            }
            for line in lines
            if line.stripe_price_id
        ]
        if not payload:
            return

        sql = load_sql(_SYNC_PRICES_BY_PLAN_SQL_PATH)
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {
                    "line_amounts": json.dumps(payload),
                    "family_ids": [str(uid) for uid in family_ids],
                },
            )
        except Exception:
            logger.error(
                "Failed to write plan-level totals for family %s",
                family_ids,
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
