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
from src.member_memberships.service.payment_sync.payment_sync_queries import (
    PaymentSyncQueries,
)
from src.member_memberships.service.payment_sync.payment_sync_stripe import (
    PaymentSyncStripe,
)
from src.member_memberships.service.payment_sync.price_writeback import (
    PriceWriteback,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.billing_parent import ParentProfile
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
        self._queries = PaymentSyncQueries(db_pool)
        self._parent = parent_resolver
        self._freeze = freeze
        self._once_discounts = once_discounts
        self._builder = builder
        self._stripe = PaymentSyncStripe(subscription_service)
        self._price_writeback = PriceWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def update_payments_recurring(
        self,
        member_id: UUID,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> PaymentsSubscriptionResponse | None:
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
            The resulting subscription response, or None if
            the subscription was cancelled (no items remaining).
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

        # ── Write back the resolved coupon links (real path) ──
        # The coupons were attached during the build; persist each
        # applied_discount_id → coupon_id (the `once` consumption handle).
        for applied_discount_id, coupon_id in params.coupon_links.items():
            await self._queries.set_applied_discount_coupon_id(
                applied_discount_id,
                coupon_id,
            )

        # ── Write back subscription ID ─────────────────────
        new_sub_id = sub_result.stripe_subscription_id if sub_result else None
        await self._queries.update_profile_sub_id(
            parent.member_id,
            new_sub_id,
        )

        # ── Mirror post-discount totals back onto CRM ──────
        await self._price_writeback.sync_prices_from_stripe(
            parent_member_id=parent.member_id,
            gym_id=parent.gym_id,
            stripe_sub_id=new_sub_id,
            stripe_account_id=stripe_account_id,
        )

        return sub_result

    async def preview_update_payments_recurring(
        self,
        member_id: UUID,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what a recurring sync would charge, with no writes.

        Runs the exact same DB-derived resolution + discount
        resolution + subscription-bucket building as
        ``update_payments_recurring``, then calls Stripe's invoice
        preview endpoint instead of mutating the subscription. No
        CRM rows are written and no subscription is created, updated,
        or cancelled — but the discount coupons ARE resolved
        (idempotent, gym-wide find-or-create), so the preview total
        reflects discounts.

        Freeze/unfreeze and the once-discount settle are intentionally
        skipped here — they write or pause, which a dry run must not do.

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

    async def resolve_parent(self, member_id: UUID) -> ParentProfile:
        """Expose parent resolution for upstream validation.

        Args:
            member_id: Any family member's profile ID.

        Returns:
            The paying parent's profile.
        """
        return await self._parent.resolve_parent(member_id)
