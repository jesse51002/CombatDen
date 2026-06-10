"""Unified writeback: persist the full sync-owned state after Stripe converges."""

import logging
from uuid import UUID

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import stripe_ts_to_gym_date
from src.sync.service.sync_queries import (
    PaymentSyncQueries,
)
from src.sync.sync_schema import SyncParams

logger = logging.getLogger(__name__)


class PaymentSyncWriteback:
    """Persists everything the sync owns, real path only, after convergence.

    Given the resolved ``SyncParams`` and the live subscription result it writes:
    the per-membership Stripe line id / next_due_date / ``applied`` status, each
    membership's own post-discount price onto ``total_price``, the coupon links
    (+ ``applied`` on the applied-discount rows), the parent's subscription id,
    ``deleted`` on cancelled rows confirmed gone, and the parent's monthly
    recurring total from Stripe's upcoming invoice. All writes go through
    ``PaymentSyncQueries``; nothing here is preview-safe — call it only on the
    real path.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._subscription_service = subscription_service

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

        # Per-membership OWN post-discount price → total_price (computed at
        # build time by PaymentSyncDiscounts, threaded through SyncParams).
        await self._queries.set_membership_post_discount_prices(
            params.membership_post_discount_amounts
        )

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

        # Parent's monthly recurring total from Stripe's upcoming invoice.
        await self._sync_parent_monthly_total(
            parent,
            new_sub_id,
            params.stripe_account_id,
        )

    async def _sync_parent_monthly_total(
        self,
        parent: ParentProfile,
        stripe_sub_id: str | None,
        stripe_account_id: str,
    ) -> None:
        """Write the parent's monthly recurring total from the upcoming invoice.

        Sums the upcoming invoice's recurring lines (proration already filtered
        out by the mapper) onto ``members.total_monthly_recurring_price``. When
        ``stripe_sub_id`` is None (the sub was fully cancelled) the total is
        zeroed. Any failure is logged at ERROR and never re-raised — Stripe is
        authoritative and a later mutation / the reconciler re-corrects the
        mirror.
        """
        amount = 0
        if stripe_sub_id:
            try:
                upcoming = (
                    await self._subscription_service.fetch_upcoming_invoice(
                        stripe_sub_id,
                        stripe_account_id,
                    )
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
            amount = sum(
                max(line.discounted_amount, 0) for line in upcoming.lines
            )
        try:
            await self._queries.set_parent_monthly_total(
                parent.member_id,
                amount,
            )
        except Exception:
            logger.error(
                "Failed to update total_monthly_recurring_price on parent %s",
                parent.member_id,
                exc_info=True,
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
                stripe_ts_to_gym_date(
                    line.current_period_end,
                    params.parent.timezone,
                ),
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
