"""Unified writeback: persist the full sync-owned state after Stripe converges."""

import logging
from collections.abc import Awaitable

from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import stripe_ts_to_gym_date
from src.shared.payer_profile import PayerProfile
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
    (+ ``applied`` on the applied-discount rows), the payer's subscription id,
    ``deleted`` on every cancelled row (the converge removed its billing), and
    the payer's monthly recurring total from Stripe's upcoming invoice. All writes go through
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
        """Persist the full sync-owned state for this convergence.

        Best-effort: every step runs under its own guard, so a failure in one
        is logged at ERROR and never aborts the rest — the writeback persists
        everything it *can*, and any step that did not land self-heals on the
        next sync / reconciler run (Stripe is authoritative). One bad coupon or
        membership row must never block a different step — notably the status
        stamp a caller's verify reads. This method never raises.
        """
        payer = params.payer
        new_sub_id = sub_result.stripe_subscription_id if sub_result else None

        # Per-membership: stamp the live line id + next_due_date + 'applied'.
        await self._run_step(
            self._apply_membership_rows(params, sub_result),
            f"apply_membership_rows payer={payer.member_id}",
        )

        # Per-membership OWN post-discount price → total_price (computed at
        # build time by PaymentSyncDiscounts, threaded through SyncParams).
        await self._run_step(
            self._queries.set_membership_post_discount_prices(
                params.membership_post_discount_amounts
            ),
            f"set_membership_post_discount_prices payer={payer.member_id}",
        )

        # Coupon links + 'applied' on the contributing applied-discount rows.
        await self._run_step(
            self._apply_coupon_links(params),
            f"apply_coupon_links payer={payer.member_id}",
        )

        # 'deleted' on every cancelled row (the converge removed its billing),
        # best-effort so one failed write can't abort the rest.
        await self._run_step(
            self._mark_removed_deleted(payer),
            f"mark_removed_deleted payer={payer.member_id}",
        )

        # Payer subscription id (or None when the sub was cancelled).
        await self._run_step(
            self._queries.update_profile_sub_id(payer.member_id, new_sub_id),
            f"update_profile_sub_id payer={payer.member_id}",
        )

        # Payer's monthly recurring total from Stripe's upcoming invoice
        # (already best-effort / never raises internally).
        await self._sync_payer_monthly_total(
            payer,
            new_sub_id,
            params.stripe_account_id,
        )

    async def _run_step(
        self,
        step: Awaitable[None],
        description: str,
    ) -> None:
        """Run one writeback step best-effort: log on failure, never re-raise.

        Mirrors the swallow-and-log policy already used for the payer
        monthly-total writeback, so a single failed write cannot abort the
        remaining writebacks.
        """
        try:
            await step
        except Exception:
            logger.error(
                "Writeback step failed (%s); continuing with the rest",
                description,
                exc_info=True,
            )

    async def _apply_coupon_links(self, params: SyncParams) -> None:
        """Write each resolved coupon link + 'applied'; guard each row.

        One bad applied-discount row is logged and skipped so the others still
        land.
        """
        for applied_discount_id, coupon_id in params.coupon_links.items():
            try:
                await self._queries.set_applied_discount_coupon_id(
                    applied_discount_id,
                    coupon_id,
                )
            except Exception:
                logger.error(
                    "Writeback: failed to link coupon %s onto applied "
                    "discount %s; continuing",
                    coupon_id,
                    applied_discount_id,
                    exc_info=True,
                )

    async def _sync_payer_monthly_total(
        self,
        payer: PayerProfile,
        stripe_sub_id: str | None,
        stripe_account_id: str,
    ) -> None:
        """Write the payer's monthly recurring total from the upcoming invoice.

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
            await self._queries.set_payer_monthly_total(
                payer.member_id,
                amount,
            )
        except Exception:
            logger.error(
                "Failed to update total_monthly_recurring_price on payer %s",
                payer.member_id,
                exc_info=True,
            )

    async def _apply_membership_rows(
        self,
        params: SyncParams,
        sub_result: PaymentsSubscriptionResponse | None,
    ) -> None:
        """Map live items → membership rows by price; stamp each row 'applied'.

        A consolidated line (one Stripe item, quantity N) maps to every one of
        the payer's memberships on that price — they all get the same line id +
        period end. Each row is stamped under its own guard so one failure does
        not block the rest (notably the status stamp a caller's verify reads).
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
            try:
                await self._queries.apply_membership_sync(
                    membership.item_id,
                    membership.member_id,
                    line.stripe_subscription_item_id,
                    stripe_ts_to_gym_date(
                        line.current_period_end,
                        params.payer.timezone,
                    ),
                )
            except Exception:
                logger.error(
                    "Writeback: failed to stamp membership row item_id=%s "
                    "member_id=%s; continuing",
                    membership.item_id,
                    membership.member_id,
                    exc_info=True,
                )

    async def _mark_removed_deleted(self, payer: PayerProfile) -> None:
        """Stamp 'deleted' on every of the payer's cancelled rows after converge.

        The desired state excludes every cancelled row by construction
        (``get_active_recurring`` drops any row with a ``cancel_date``), so a
        successful converge means each cancelled row's billing is gone from
        Stripe: its line was removed, or its share of a consolidated line was
        decremented. The line id itself may still be live for the payer's
        remaining members on that price — which is why the rows are stamped
        unconditionally rather than diffed against the live line ids (a
        live-line check would never stamp a row removed from a shared line).
        """
        cancelled = await self._queries.get_cancelled_recurring(payer.member_id)
        if not cancelled:
            return
        await self._queries.mark_memberships_deleted(cancelled)
