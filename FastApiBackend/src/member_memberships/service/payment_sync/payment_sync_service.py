"""Service for syncing membership payment state with Stripe."""

from __future__ import annotations

import logging
from typing import Literal
from uuid import UUID, uuid4

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    PaymentSyncBuilder,
)
from src.member_memberships.service.payment_sync.payment_sync_freeze import (
    PaymentSyncFreeze,
)
from src.member_memberships.service.payment_sync.payment_sync_once_discounts import (
    PaymentSyncOnceDiscounts,
)
from src.member_memberships.service.payment_sync.payment_sync_stripe import (
    PaymentSyncStripe,
)
from src.member_memberships.service.payment_sync.payment_sync_writeback import (
    PaymentSyncWriteback,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)


class PaymentSyncService:
    """Syncs membership payment state with Stripe.

    Thin orchestrator over focused sub-services: resolve the paying parent
    (``BillingParentResolver``), re-apply the parent's freeze window
    (``PaymentSyncFreeze``), finalize the once-discount lifecycle
    (``PaymentSyncOnceDiscounts``), build the desired subscription bucket +
    resolved discount coupons from the DB (``PaymentSyncBuilder`` →
    ``PaymentSyncDiscounts``, at build time so preview reflects discounts), then
    create/update/cancel the Stripe subscription (``PaymentSyncStripe``) and
    write the results back. The desired state is derived purely from the DB —
    there are no imperative add/cancel inputs.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
        parent_resolver: BillingParentResolver,
        freeze: PaymentSyncFreeze,
        once_discounts: PaymentSyncOnceDiscounts,
        builder: PaymentSyncBuilder,
    ) -> None:
        self._parent = parent_resolver
        self._freeze = freeze
        self._once_discounts = once_discounts
        self._builder = builder
        self._stripe = PaymentSyncStripe(subscription_service)
        self._writeback = PaymentSyncWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def update_payments_recurring(
        self,
        member_id: UUID,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> None:
        """Sync a member's recurring memberships with Stripe.

        Re-derives the full desired subscription state from the DB — the active
        recurring memberships, each carrying its applied discounts — and
        converges Stripe onto it; there are no imperative add/cancel inputs.
        Resolves the paying parent, re-applies the parent's intrinsic freeze
        state (maintenance), finalizes once discounts, computes and attaches
        each consolidated line's coupon, then reconciles the monthly
        subscription.

        The explicit freeze/unfreeze action lives in the dedicated
        ``PaymentSyncFreeze`` service, not here — this path only re-applies the
        freeze the parent already carries.

        Args:
            member_id: Any family member's profile ID.

        Returns:
            None. The sync writes everything it owns back to the DB (line ids,
            next_due_date, sync status, coupon links, sub id, price totals);
            callers read the DB (the ``applied`` status) to confirm it landed.
            Use ``preview_update_payments_recurring`` for the invoice figures.
        """
        parent, stripe_account_id = await self._parent.resolve(member_id)

        # ── Maintenance freeze re-apply first ─────────────
        # Re-syncs pause_collection to the parent's DB freeze window
        # so a membership change on a frozen account keeps the pause
        # in the correct billing order, before any item change.
        await self._freeze.sync_freeze_state(
            parent,
            stripe_account_id,
            idempotency_key=idempotency_key,
        )

        # ── Finalize once discounts in the DB (pre-sync) ──
        # Stamps any `once` discount Stripe already invoiced, so the
        # build below reads the settled DB and the convergence drops
        # the consumed ones by their stamped end_date.
        await self._once_discounts.sync_once_discounts(
            parent,
            stripe_account_id,
        )

        # The build resolves the discount coupons onto the bucket and collects
        # the applied-discount→coupon links (for both real and preview).
        params = await self._builder.build_sync_params(
            parent,
            stripe_account_id,
        )

        sub_result = await self._stripe.execute_sync(
            params.bucket,
            parent,
            stripe_account_id,
            idempotency_key=idempotency_key,
            pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
            proration_behavior=proration_behavior,
        )

        # ── Persist the full sync-owned state (real path only) ──
        # Per-membership line id / next_due_date / 'applied' status, coupon
        # links, 'deleted' stamping, sub id, and post-discount price totals.
        await self._writeback.write(params, sub_result)

    async def preview_update_payments_recurring(
        self,
        member_id: UUID,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what a recurring sync would charge.

        Runs the same DB-derived resolution + discount resolution +
        subscription-bucket building as ``update_payments_recurring``
        (the discount coupons ARE resolved — idempotent, gym-wide
        find-or-create — so the preview total reflects discounts), then
        calls Stripe's invoice preview endpoint instead of mutating the
        subscription. No subscription is created, updated, or cancelled.

        The once-discount settle DOES run here, same as the real path:
        stamping a consumed ``once``'s ``end_date`` is a settled fact
        (Stripe already invoiced it), not a hypothetical, so the preview
        must reflect it dropping off. What a dry run skips is the
        **freeze re-apply** (it pauses billing) and the **convergence
        writeback** (line ids / sync status / sub id / price totals) —
        none of the sync's own desired-state results are persisted.

        Returns:
            An invoice preview, or ``None`` if the resulting bucket
            would cancel the subscription (no items remaining) —
            a cancellation has no upcoming invoice.
        """
        parent, stripe_account_id = await self._parent.resolve(member_id)

        # ── Finalize once discounts in the DB (pre-sync) ──
        # Stamps any `once` discount Stripe already invoiced, so the
        # build below reads the settled DB and the convergence drops
        # the consumed ones by their stamped end_date.
        await self._once_discounts.sync_once_discounts(
            parent,
            stripe_account_id,
        )

        params = await self._builder.build_sync_params(
            parent,
            stripe_account_id,
            preview=True,
        )
        return await self._stripe.preview_execute_sync(
            params.bucket,
            parent,
            stripe_account_id,
            proration_behavior,
        )

    async def bulk_payment_sync(
        self,
        member_ids: list[UUID],
    ) -> None:
        """Re-sync payment state for multiple members.

        A fresh idempotency key is generated per member since bulk
        sync is a background re-sync — there is no client-supplied
        key, and each member's sync is an independent operation.

        Args:
            member_ids: Members whose memberships need sync.
        """
        for member_id in member_ids:
            try:
                await self.update_payments_recurring(
                    member_id,
                    idempotency_key=uuid4(),
                )
            except PaymentsResourceNotFoundError:
                logger.error(
                    "Stripe resource not found during payment sync for %s",
                    member_id,
                    exc_info=True,
                )
            except Exception:
                logger.error(
                    "Payment sync failed for %s",
                    member_id,
                    exc_info=True,
                )
