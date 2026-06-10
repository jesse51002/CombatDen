"""Sync the ``once``-discount lifecycle in the DB before the sync converges.

The sync should read a DB that is already in the state it should be in, and only
write its convergence results at the end. Finalizing ``once`` discounts —
detecting the ones Stripe has already invoiced and stamping their ``end_date`` —
is a precondition, not part of the convergence. This component is that
precondition; it is also the scheduled reconciler's core duty, so it stands
alone (DI-injectable) for reuse.
"""

from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.sync.service.sync_queries import (
    PaymentSyncQueries,
)


class PaymentSyncOnceDiscounts:
    """Finalizes the ``once``-discount lifecycle in the DB before convergence.

    Queries the family's attached-but-unconsumed ``once`` discounts (the DB does
    the ``once`` + no-end_date + has-coupon filtering), reads the live
    subscription's coupons — the only thing that can tell a consumed ``once``
    from a pending one, since Stripe owns billing outcomes — and stamps the
    ``end_date`` of every one whose coupon Stripe has already invoiced (dropped
    from the live set). After this runs, the convergence's pure ``end_date``
    exclusion drops the consumed ones, so it needs no live-Stripe read.

    Only ``once`` discounts need this — an ongoing discount's lifetime is its
    ``end_date`` (pure date logic, dropped at convergence).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._subscriptions = subscription_service

    async def sync_once_discounts(
        self,
        parent: ParentProfile,
        stripe_account_id: str,
    ) -> None:
        """Stamp every consumed ``once`` discount for the parent's family.

        A no-op when the family has no unconsumed ``once`` discounts or there is
        no live subscription to read (a brand-new sub has invoiced nothing, so
        every ``once`` is still pending).
        """
        family_ids = await self._queries.get_family_ids(parent)
        once_discounts = await self._queries.get_unconsumed_once_discounts(
            family_ids,
        )
        if not once_discounts:
            return

        current_coupon_ids = await self._current_coupon_ids(
            parent.stripe_sub_id_month,
            stripe_account_id,
        )
        # Set math: a candidate's coupon missing from the live subscription
        # means Stripe already invoiced it (consumed). Stamp the whole consumed
        # set in one query — map the consumed coupons back to their rows
        # (a coupon can be shared by several same-value `once` discounts).
        consumed_coupons = {d.stripe_coupon_id for d in once_discounts} - current_coupon_ids
        if not consumed_coupons:
            return

        consumed_ids = [
            d.applied_discount_id
            for d in once_discounts
            if d.stripe_coupon_id in consumed_coupons
        ]
        await self._queries.mark_once_consumed(
            consumed_ids,
            gym_today(parent.timezone),
        )

    async def _current_coupon_ids(
        self,
        existing_sub_id: str | None,
        stripe_account_id: str,
    ) -> set[str]:
        """Read the coupon ids currently on the live subscription.

        Empty when there is no existing subscription (a brand-new sub has no
        prior discounts, so every ``once`` discount is still pending).
        """
        if not existing_sub_id:
            return set()

        sub = await self._subscriptions.get_subscription(
            existing_sub_id,
            stripe_account_id,
        )
        coupon_ids: set[str] = set(sub.discounts)
        for item in sub.items:
            coupon_ids.update(item.discounts)
        return coupon_ids
