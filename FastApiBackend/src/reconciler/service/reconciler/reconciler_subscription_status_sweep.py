"""SubscriptionStatusSweep — absorb Stripe lifecycle outcomes into the CRM.

The push sync only ever pushes CRM -> Stripe; it never reads a sub's actual
lifecycle. This sweep is the missing Stripe -> CRM half: for each active billing
family it reads the live subscription's status and absorbs the terminal outcome.

- not found / ``canceled`` -> the sub is gone -> ``SubscriptionCancellationAbsorber``
  (CRM-only).
- ``past_due`` / ``unpaid`` -> **record-only**. There is no past_due/delinquent
  state in the CRM; "overdue" is derived from ``next_due_date`` and is refreshed
  by the invoice fetcher (the failed-charge row), not by a membership change.
- ``active`` / anything else -> no-op (the push sweep converges config drift).

The status is read **explicitly** off a direct ``subscriptions.retrieve`` — NOT
via the engine's ``get_subscription`` (which raises on a canceled sub). Branching
on a returned status value, rather than catching that raise, keeps this sweep
correct even if ``get_subscription``'s raise-on-canceled behavior is ever changed
(otherwise it would be a silent, hidden bug — absorption would just stop). A
genuine not-found (404) reads as gone; any other Stripe error is counted and does
NOT absorb (never cancel a member off a transient error).

Runs as its own pass before the push sweep ("read status... then run sync"); the
absorber self-contains its writes, so there is no per-member pipeline to fuse.
"""

import logging

import stripe
from sqlalchemy import text

from src.member_memberships.service.memberships.member_memberships_cancel_absorber import (
    SubscriptionCancellationAbsorber,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SWEEP_NAME = "subscription_status"
SUBSCRIPTION_STATUS_CANCELED = "canceled"
OVERDUE_STATUSES = frozenset({"past_due", "unpaid"})


class SubscriptionStatusSweep:
    """Read each active family's live sub status and absorb terminal outcomes."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_client: PaymentsStripeClient,
        gym_stripe_service: GymStripeService,
        cancellation_absorber: SubscriptionCancellationAbsorber,
    ) -> None:
        self._db_pool = db_pool
        self._stripe = stripe_client.client
        self._gym_stripe = gym_stripe_service
        self._cancellation_absorber = cancellation_absorber

    async def run(self) -> SweepResult:
        """Read every active billing family's sub and absorb terminal states."""
        members = await self._list_billing_members()
        result = SweepResult(name=SWEEP_NAME, processed=len(members))
        for member in members:
            await self._absorb_one(member, result)
        logger.info(
            "Subscription status: processed=%d cancelled=%d errors=%d",
            result.processed,
            result.changed,
            result.errors,
        )
        return result

    async def _list_billing_members(self) -> list[dict]:
        """Active paying parents with member_id, gym_id, stripe_sub_id_month."""
        sql = load_sql(SQL_DIR / "reconciler_active_billing_members.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [dict(row) for row in res.mappings().all()]

    async def _read_status(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
    ) -> str | None:
        """The live Stripe subscription status, or ``None`` if not found.

        Reads the status directly so callers branch on a value, not on an
        exception. A genuine not-found (``InvalidRequestError`` / 404) returns
        ``None``; any other Stripe error propagates (the caller counts it and
        does not absorb).
        """
        opts = PaymentsStripeClient.connect_opts_readonly(stripe_account_id)
        try:
            sub = await self._stripe.v1.subscriptions.retrieve_async(
                stripe_subscription_id,
                options=opts,
            )
        except stripe.InvalidRequestError:
            return None
        return sub.status

    async def _absorb_one(self, member: dict, result: SweepResult) -> None:
        """Read one family's live sub status and absorb its outcome."""
        sub_id = member["stripe_sub_id_month"]
        if not sub_id:
            return  # no live sub to read

        try:
            account_id = await self._gym_stripe.get_stripe_account_id(
                member["gym_id"],
            )
            status = await self._read_status(sub_id, account_id)
        except Exception:
            logger.error(
                "Subscription status: failed to read sub %s for member %s",
                sub_id,
                member["member_id"],
                exc_info=True,
            )
            result.errors += 1
            return

        # Gone (not found) or explicitly canceled -> absorb into the CRM.
        if status is None or status == SUBSCRIPTION_STATUS_CANCELED:
            result.changed += await self._cancellation_absorber.absorb(
                member["member_id"],
            )
            return

        if status in OVERDUE_STATUSES:
            logger.info(
                "Subscription %s for member %s is %s; recorded by invoice "
                "fetcher (overdue is date-derived), no membership change",
                sub_id,
                member["member_id"],
                status,
            )
        # active / other -> no-op; the push sweep converges config drift.
