"""Service for syncing membership payment state with Stripe."""

from __future__ import annotations

import asyncio
import logging
from typing import Literal
from uuid import UUID, uuid4

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.payer_profile import PayerProfile
from src.shared.payer_resolver import PayerResolver
from src.shared.paying_member_lock import LockBusyError, PayingMemberLock
from src.sync.service.sync_builder import (
    PaymentSyncBuilder,
)
from src.sync.service.sync_cancel import (
    PaymentSyncCancel,
)
from src.sync.service.sync_once_discounts import (
    PaymentSyncOnceDiscounts,
)
from src.sync.service.sync_stripe import (
    PaymentSyncStripe,
)
from src.sync.service.sync_writeback import (
    PaymentSyncWriteback,
)

logger = logging.getLogger(__name__)


class PaymentSyncService:
    """Syncs membership payment state with Stripe.

    Thin orchestrator over focused sub-services: resolve the PAYER
    (``PayerResolver.resolve_payer`` — the passed id IS the payer; no parent
    redirect), finalize the once-discount lifecycle
    (``PaymentSyncOnceDiscounts``), build the desired subscription bucket +
    resolved discount coupons from the payer's rows (``PaymentSyncBuilder`` →
    ``PaymentSyncDiscounts``, at build time so preview reflects discounts), then
    create/update/cancel the payer's Stripe subscription (``PaymentSyncStripe``)
    and write the results back. One sync call = one payer's subscription; the
    desired state is derived purely from the DB (``paid_by_member_id`` scope) —
    there are no imperative add/cancel inputs and no family reads.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
        payer_resolver: PayerResolver,
        once_discounts: PaymentSyncOnceDiscounts,
        builder: PaymentSyncBuilder,
        paying_lock: PayingMemberLock,
    ) -> None:
        self._payer = payer_resolver
        self._once_discounts = once_discounts
        self._builder = builder
        self._paying_lock = paying_lock
        self._stripe = PaymentSyncStripe(subscription_service)
        self._cancel = PaymentSyncCancel(db_pool)
        self._writeback = PaymentSyncWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def update_payments_recurring(
        self,
        payer_member_id: UUID,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> None:
        """Sync a payer's recurring memberships with Stripe.

        Re-derives the full desired subscription state from the DB — every
        active recurring membership whose ``paid_by_member_id`` is this payer,
        each carrying its applied discounts — and converges the payer's
        subscription onto it; there are no imperative add/cancel inputs.
        Resolves the payer's own profile, finalizes once discounts, computes
        and attaches each consolidated line's coupon, then reconciles the
        monthly subscription.

        Freeze is out of this path entirely: the explicit freeze/unfreeze
        action owns ``pause_collection`` (via ``PaymentSyncFreeze``), and
        because the pause is subscription-level it persists across item changes
        — so a membership op on a frozen payer needs no freeze re-apply here.

        Args:
            payer_member_id: The PAYER whose subscription to converge (a
                membership row's ``paid_by_member_id`` — never resolved up to
                a parent).

        Returns:
            None. The sync writes everything it owns back to the DB (line ids,
            next_due_date, sync status, coupon links, sub id, price totals);
            callers read the DB (the ``applied`` status) to confirm it landed.
            Use ``preview_update_payments_recurring`` for the invoice figures.
        """
        payer, stripe_account_id = await self._payer.resolve_payer_with_account(
            payer_member_id,
        )

        try:
            # ── Finalize once discounts in the DB (pre-sync) ──
            # Stamps any `once` discount Stripe already invoiced, so the
            # build below reads the settled DB and the convergence drops
            # the consumed ones by their stamped end_date.
            await self._once_discounts.sync_once_discounts(
                payer,
                stripe_account_id,
            )

            # The build resolves the discount coupons onto the bucket and
            # collects the applied-discount→coupon links (real + preview).
            params = await self._builder.build_sync_params(
                payer,
                stripe_account_id,
            )

            sub_result = await self._stripe.execute_sync(
                params.bucket,
                payer,
                stripe_account_id,
                idempotency_key=idempotency_key,
                pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
                proration_behavior=proration_behavior,
            )
        except PaymentsResourceNotFoundError as exc:
            await self._handle_lost_subscription(payer, exc)
        else:
            # ── Persist the full sync-owned state (real path only) ──
            # Per-membership line id / next_due_date / 'applied' status, coupon
            # links, 'deleted' stamping, sub id, and post-discount price totals.
            await self._writeback.write(params, sub_result)

    async def _handle_lost_subscription(
        self,
        payer: PayerProfile,
        exc: PaymentsResourceNotFoundError,
    ) -> None:
        """Record a gone subscription as a cancellation, then re-raise.

        Stripe reports the payer's monthly subscription gone (canceled /
        not-found) — surfaced by the once-settle live read or by
        ``execute_sync``'s update/cancel of the existing sub. Record the
        cancellation in the CRM — cancel the live recurring memberships this
        payer bills + null the payer's sub id — instead of recreating the sub
        (which would re-bill a member Stripe already let go). Memberships paid
        by OTHER payers in the family are untouched. Then **re-raise**: the
        requested converge did not happen (the payer's rows were cancelled
        instead), so the caller learns it failed and reverts / surfaces the
        error.

        Gated: ONLY ``resource_type == subscription`` is a lost sub to cancel.
        Any other not-found — an item-level drift, a missing price, a missing
        coupon — re-raises untouched (a stale item id must never cancel a live
        payer).
        """
        if exc.resource_type == StripeResourceType.subscription:
            await self._cancel.cancel_dead_subscription(payer)
        raise exc

    async def preview_update_payments_recurring(
        self,
        payer_member_id: UUID,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> DueNowVsRecurringPreview | None:
        """Preview what a recurring sync would charge, as a split.

        The single preview entry point for every surface. Runs the same
        DB-derived resolution + discount resolution + subscription-bucket
        building as ``update_payments_recurring`` (the discount coupons
        ARE resolved — idempotent, gym-wide find-or-create — so the
        preview reflects discounts), then previews Stripe's invoice
        instead of mutating the subscription. No subscription is created,
        updated, or cancelled.

        The once-discount settle DOES run here, same as the real path:
        stamping a consumed ``once``'s ``end_date`` is a settled fact
        (Stripe already invoiced it), not a hypothetical, so the preview
        must reflect it dropping off. What a dry run skips is the
        **convergence writeback** (line ids / sync status / sub id / price
        totals) — none of the sync's own desired-state results are persisted.

        Returns:
            A ``{due_now, recurring}`` split, or ``None`` if the bucket
            would cancel the subscription (no items remaining) —
            a cancellation has no upcoming invoice.
        """
        payer, stripe_account_id = await self._payer.resolve_payer_with_account(
            payer_member_id,
        )

        try:
            # ── Finalize once discounts in the DB (pre-sync) ──
            # Stamps any `once` discount Stripe already invoiced, so the
            # build below reads the settled DB and the convergence drops
            # the consumed ones by their stamped end_date.
            await self._once_discounts.sync_once_discounts(
                payer,
                stripe_account_id,
            )

            params = await self._builder.build_sync_params(
                payer,
                stripe_account_id,
                preview=True,
            )
            return await self._stripe.preview_execute_sync(
                params.bucket,
                payer,
                stripe_account_id,
                proration_behavior,
            )
        except PaymentsResourceNotFoundError as exc:
            # Same settled-fact rule as the once-settle that runs above: a sub
            # Stripe has cancelled is reality, not a hypothetical, so even a
            # preview records the cancellation (then re-raises — there is no
            # invoice to preview against a gone sub).
            await self._handle_lost_subscription(payer, exc)

    async def bulk_payment_sync(
        self,
        payer_member_ids: list[UUID],
    ) -> None:
        """Re-sync payment state for multiple payers.

        A fresh idempotency key is generated per payer since bulk sync is a
        background re-sync — there is no client-supplied key, and each payer's
        sync is an independent operation.

        Each payer's sync is guarded on its payer lock key, so the batch never
        collides with a concurrent op on the same payer; different payers are
        independent. Payers that fail a pass (most often a transient
        ``LockBusyError`` — the payer was momentarily busy) are collected and
        **retried in a loop, up to ``settings.bulk_sync_max_retries`` times**. The
        ``settings.bulk_sync_retry_delay_seconds`` wait happens **after** a pass that left
        failures and only before another attempt — never after the final attempt.
        Anything still failing once the retries are exhausted is logged.

        Args:
            payer_member_ids: Payers whose subscriptions need sync.
        """
        pending = payer_member_ids
        for attempt in range(settings.bulk_sync_max_retries + 1):
            pending = await self._sync_members(pending)
            if not pending:
                return
            # Failures remain — wait before retrying, but never after the last
            # attempt (we're giving up, not retrying).
            if attempt < settings.bulk_sync_max_retries:
                logger.info(
                    "Bulk payment sync: %d payers failed; retry %d/%d in %ds",
                    len(pending),
                    attempt + 1,
                    settings.bulk_sync_max_retries,
                    settings.bulk_sync_retry_delay_seconds,
                )
                await asyncio.sleep(settings.bulk_sync_retry_delay_seconds)
        logger.error(
            "Bulk payment sync: %d payers still failed after %d retries: %s",
            len(pending),
            settings.bulk_sync_max_retries,
            pending,
        )

    async def _sync_members(self, payer_member_ids: list[UUID]) -> list[UUID]:
        """Sync each payer under its lock; return the ones that failed.

        Each failure (a busy payer, a missing Stripe resource, or any other
        error) is logged and the payer is added to the returned list so the
        caller can retry the batch's failures.
        """
        failed: list[UUID] = []
        for payer_member_id in payer_member_ids:
            try:
                async with self._paying_lock.lock([payer_member_id]):
                    await self.update_payments_recurring(
                        payer_member_id,
                        idempotency_key=uuid4(),
                    )
            except LockBusyError:
                logger.warning(
                    "Payment sync deferred (payer busy) for %s",
                    payer_member_id,
                )
                failed.append(payer_member_id)
            except PaymentsResourceNotFoundError:
                logger.error(
                    "Stripe resource not found during payment sync for %s",
                    payer_member_id,
                    exc_info=True,
                )
                failed.append(payer_member_id)
            except Exception:
                logger.error(
                    "Payment sync failed for %s",
                    payer_member_id,
                    exc_info=True,
                )
                failed.append(payer_member_id)
        return failed

    async def settle_once_discounts(self, payer_member_id: UUID) -> None:
        """Finalize the payer's consumed ``once`` discounts (stamp end_date).

        The same pre-sync once-settle ``update_payments_recurring`` runs,
        exposed on its own so the ``invoice.paid`` webhook can call it the moment
        Stripe invoices a subscription: a consumed ``once`` coupon drops off the
        payer's live sub, and this records its ``end_date`` promptly instead of
        waiting for the next manual op (or the reconciler sweep). Resolves the
        payer's own profile, then runs the settle. A no-op when the payer has no
        unconsumed ``once`` discounts.

        The settle itself does **not** lock — its sole caller (the
        ``invoice.paid`` webhook) wraps it in ``PayingMemberLock`` so it can't
        race a concurrent sync on the same payer.

        Args:
            payer_member_id: The payer (a membership row's
                ``paid_by_member_id``).
        """
        payer, stripe_account_id = await self._payer.resolve_payer_with_account(
            payer_member_id,
        )
        await self._once_discounts.sync_once_discounts(
            payer,
            stripe_account_id,
        )
