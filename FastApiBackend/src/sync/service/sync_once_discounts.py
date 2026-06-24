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
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.payer_profile import PayerProfile
from src.sync.service.sync_queries import (
    PaymentSyncQueries,
)


class PaymentSyncOnceDiscounts:
    """Finalizes the ``once``-discount lifecycle in the DB before convergence.

    Queries the PAYER's attached-but-unconsumed ``once`` discounts (the DB does
    the ``once`` + no-end_date + has-coupon filtering, scoped by
    ``paid_by_member_id``), reads the coupons Stripe will actually APPLY on the
    payer's next invoice (``create_preview``) — the only thing that can tell a
    consumed ``once`` from a pending one, since Stripe owns billing outcomes —
    and stamps the ``end_date`` of every one whose coupon is NOT on that next
    invoice (Stripe already redeemed it). Reading the next invoice's APPLIED
    discounts, not the sub's ATTACHED coupons, is deliberate: Stripe leaves a
    redeemed ``once``'s discount object on the item (it does whenever another
    discount coexists), so the attached set misreads a consumed ``once`` as
    pending. The candidate set and the invoice read target the SAME payer
    subscription. After this runs, the convergence's pure ``end_date`` exclusion
    drops the consumed ones, so it needs no live-Stripe read.

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
        payer: PayerProfile,
        stripe_account_id: str,
    ) -> None:
        """Stamp every consumed ``once`` discount on the payer's memberships.

        A no-op when the payer has no unconsumed ``once`` discounts or there is
        no live subscription to read (a brand-new sub has invoiced nothing, so
        every ``once`` is still pending).
        """
        once_discounts = await self._queries.get_unconsumed_once_discounts(
            payer.member_id,
        )
        if not once_discounts:
            return

        applied_coupon_ids = await self._next_invoice_coupon_ids(
            payer.stripe_sub_id_month,
            stripe_account_id,
        )
        # Set math: a candidate's coupon NOT applied on the next invoice means
        # Stripe already redeemed it (consumed) — Stripe never applies a `once`
        # twice, so it drops off the upcoming invoice even though its discount
        # object can linger on the item. Stamp the whole consumed set in one
        # query — map the consumed coupons back to their rows (a coupon can be
        # shared by several same-value `once` discounts).
        consumed_coupons = {d.stripe_coupon_id for d in once_discounts} - applied_coupon_ids
        if not consumed_coupons:
            return

        consumed_ids = [
            d.applied_discount_id
            for d in once_discounts
            if d.stripe_coupon_id in consumed_coupons
        ]
        await self._queries.mark_once_consumed(
            consumed_ids,
            gym_today(payer.timezone),
        )

    async def _next_invoice_coupon_ids(
        self,
        existing_sub_id: str | None,
        stripe_account_id: str,
    ) -> set[str]:
        """Coupon ids Stripe will APPLY on the subscription's next invoice.

        A ``once`` whose coupon is attached to the sub but absent here has been
        redeemed — Stripe won't apply it again — even though its discount object
        can linger on the item. Empty when there is no existing subscription (a
        brand-new sub has no prior discounts, so every ``once`` is still
        pending).
        """
        if not existing_sub_id:
            return set()

        return await self._subscriptions.upcoming_applied_coupon_ids(
            existing_sub_id,
            stripe_account_id,
        )
