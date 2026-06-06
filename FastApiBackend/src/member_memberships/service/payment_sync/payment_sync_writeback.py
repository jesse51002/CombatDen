"""Unified writeback: persist the full sync-owned state after Stripe converges."""

from datetime import UTC, date, datetime
from uuid import UUID

from src.member_memberships.schema.payment_sync_schema import SyncParams
from src.member_memberships.service.payment_sync.payment_sync_queries import (
    PaymentSyncQueries,
)
from src.member_memberships.service.payment_sync.price_writeback import (
    PriceWriteback,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool


class PaymentSyncWriteback:
    """Persists everything the sync owns, real path only, after convergence.

    Given the resolved ``SyncParams`` and the live subscription result it writes:
    the per-membership Stripe line id / next_due_date / ``applied`` status, the
    coupon links (+ ``applied`` on the applied-discount rows), the parent's
    subscription id, ``deleted`` on cancelled rows confirmed gone, and the
    post-discount price totals (delegated to ``PriceWriteback``). All writes go
    through ``PaymentSyncQueries``; nothing here is preview-safe — call it only on
    the real path.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._prices = PriceWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def write(
        self,
        params: SyncParams,
        sub_result: PaymentsSubscriptionResponse | None,
    ) -> None:
        """Persist the full sync-owned state for this convergence."""
        parent = params.parent
        new_sub_id = sub_result.stripe_subscription_id if sub_result else None

        # Per-membership: stamp the live line id + next_due_date + 'applied'.
        await self._apply_membership_rows(params, sub_result)

        # Coupon links + 'applied' on the contributing applied-discount rows.
        for applied_discount_id, coupon_id in params.coupon_links.items():
            await self._queries.set_applied_discount_coupon_id(
                applied_discount_id,
                coupon_id,
            )

        # 'deleted' on cancelled rows confirmed gone from the live sub.
        await self._mark_removed_deleted(parent, sub_result)

        # Parent subscription id (or None when the sub was cancelled).
        await self._queries.update_profile_sub_id(parent.member_id, new_sub_id)

        # Post-discount price totals (per-plan + parent monthly), delegated.
        await self._prices.sync_prices_from_stripe(
            parent_member_id=parent.member_id,
            gym_id=parent.gym_id,
            stripe_sub_id=new_sub_id,
            stripe_account_id=params.stripe_account_id,
        )

    async def _apply_membership_rows(
        self,
        params: SyncParams,
        sub_result: PaymentsSubscriptionResponse | None,
    ) -> None:
        """Map live items → membership rows by price; stamp each row 'applied'.

        A consolidated line (one Stripe item, quantity N) maps to every family
        membership on that price — they all get the same line id + period end.
        """
        items_by_price = {
            item.stripe_price_id: item
            for item in (sub_result.items if sub_result else [])
        }
        for membership in params.memberships:
            line = items_by_price.get(membership.stripe_price_id)
            if line is None:
                # No live line for this price (shouldn't happen for an active
                # row) — skip; the next sync picks it up.
                continue
            await self._queries.apply_membership_sync(
                membership.item_id,
                membership.member_id,
                line.stripe_subscription_item_id,
                self._period_end_to_date(line.current_period_end),
            )

    async def _mark_removed_deleted(
        self,
        parent: ParentProfile,
        sub_result: PaymentsSubscriptionResponse | None,
    ) -> None:
        """Stamp 'deleted' on cancelled rows whose line is gone from the sub."""
        family_ids = await self._queries.get_family_ids(parent)
        cancelled = await self._queries.get_cancelled_recurring(family_ids)
        if not cancelled:
            return
        live_item_ids = {
            item.stripe_subscription_item_id
            for item in (sub_result.items if sub_result else [])
        }
        removed: list[UUID] = [
            item_id
            for item_id, stripe_item_id in cancelled.items()
            if stripe_item_id not in live_item_ids
        ]
        await self._queries.mark_memberships_deleted(removed)

    @staticmethod
    def _period_end_to_date(period_end: int) -> date:
        """Convert a Stripe unix current_period_end into a UTC date."""
        return datetime.fromtimestamp(period_end, tz=UTC).date()
