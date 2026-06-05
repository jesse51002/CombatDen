"""Service for syncing membership payment state with Stripe."""

from __future__ import annotations

import logging
from datetime import date
from uuid import UUID, uuid4

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    AppliedDiscountSnapshot,
    IntervalBucket,
    IntervalDesiredItem,
    LineDiscountPlan,
    ParentProfile,
    SyncItem,
    SyncParams,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    build_desired_items,
    build_subscription_bucket,
    map_add_ids_to_intervals,
    plan_line_discounts,
)
from src.member_memberships.service.payment_sync.payment_sync_coupons import (
    PaymentSyncCoupons,
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
    PaymentsSubscriptionDesiredItem,
    PaymentsSubscriptionResponse,
    SubscriptionItemDiscount,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today

logger = logging.getLogger(__name__)


class MembershipPaymentSyncService:
    """Syncs membership payment state with Stripe.

    Orchestrates sub-services to resolve linked accounts, build the desired
    subscription state, compute each consolidated line's discount coupon, and
    create/update/cancel the Stripe subscription. Linked-discount
    recalculation is gone — family discounts are frozen snapshot rows; the
    sync-time coupon step (``_attach_computed_coupons``) reads the live Stripe
    discounts, aggregates each consolidated line (percent ÷ quantity, summed
    dollars), find-or-creates the deterministic coupon, attaches it, and writes
    the resolved stripe_coupon_id back onto the contributing snapshots.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
        gym_stripe_service: GymStripeService,
        stripe_client: PaymentsStripeClient,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._stripe = PaymentSyncStripe(subscription_service)
        self._subscriptions = subscription_service
        self._coupons = PaymentSyncCoupons(stripe_client)
        self._gym_stripe = gym_stripe_service
        self._price_writeback = PriceWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def update_payments_recurring(
        self,
        member_id: UUID,
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
        idempotency_key: UUID,
        freeze_end_date: date | None = None,
        unfreeze: bool = False,
        pay_first_invoice_out_of_band: bool = False,
    ) -> PaymentsSubscriptionResponse | None:
        """Sync a member's recurring memberships with Stripe.

        Resolves to the paying parent account, applies any
        freeze/unfreeze action first, computes and attaches each
        consolidated line's discount coupon from the family's
        applied-discount snapshots, then reconciles the monthly
        Stripe subscription.

        Explicit freeze/unfreeze cannot be combined with
        membership changes — billing order matters on Stripe,
        so these must be separate operations.

        Args:
            member_id: Any family member's profile ID.
            add_ids: New items to add to the subscription.
            cancel_ids: Items to remove from the subscription.
            freeze_end_date: Explicitly freeze with this end date.
            unfreeze: Explicitly unfreeze the subscription.

        Returns:
            The resulting subscription response, or None if
            the subscription was cancelled (no items remaining).

        Raises:
            ValueError: If membership changes are combined with
                freeze/unfreeze, or if both freeze and unfreeze
                are requested.
        """
        self._validate_freeze_params(add_ids, cancel_ids, freeze_end_date, unfreeze)

        params = await self._build_sync_params(member_id, add_ids, cancel_ids)
        parent = params.parent
        stripe_account_id = params.stripe_account_id

        # ── Freeze/unfreeze first ─────────────────────────
        await self._stripe.sync_freeze_state(
            parent.stripe_sub_id_month,
            parent,
            stripe_account_id,
            idempotency_key=idempotency_key,
            freeze_end_date=freeze_end_date,
            unfreeze=unfreeze,
        )

        # ── Compute + attach this cycle's coupons ─────────
        # Reads the live subscription's current discounts (the once-consumption
        # gate), aggregates each consolidated line, find-or-creates the coupon,
        # attaches it to the bucket, and writes each resolved coupon (and any
        # `once` consumption) back onto the contributing snapshots.
        await self._attach_computed_coupons(
            params.bucket,
            params.snapshots,
            parent,
            stripe_account_id,
        )

        sub_result = await self._stripe.execute_sync(
            params.bucket,
            parent,
            stripe_account_id,
            idempotency_key=idempotency_key,
            pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
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
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what a recurring sync would charge, with no writes.

        Runs the exact same resolution, validation, and
        subscription-bucket building as
        ``update_payments_recurring``, then calls Stripe's invoice
        preview endpoint instead of mutating the subscription. No
        CRM rows are written, no Stripe resources are created,
        updated, or cancelled.

        Freeze/unfreeze is intentionally unsupported here — a
        pause_collection change produces no invoice to preview.

        Returns:
            An invoice preview, or ``None`` if the resulting bucket
            would cancel the subscription (no items remaining) —
            a cancellation has no upcoming invoice.
        """
        self._validate_freeze_params(add_ids, cancel_ids, None, False)

        params = await self._build_sync_params(
            member_id,
            add_ids,
            cancel_ids,
        )
        return await self._stripe.preview_execute_sync(
            params.bucket,
            params.parent,
            params.stripe_account_id,
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
                    add_ids=[],
                    cancel_ids=[],
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
        return await self._queries.resolve_parent(member_id)

    # ── Sync-Time Coupon Computation ────────────────────────────

    async def _attach_computed_coupons(
        self,
        bucket: IntervalBucket,
        snapshots: list[AppliedDiscountSnapshot],
        parent: ParentProfile,
        stripe_account_id: str,
    ) -> None:
        """Compute, attach, and write back each line's coupon(s).

        Reads the live subscription's current discounts so the
        ``once``-consumption gate can tell pending coupons from invoiced
        ones, plans each consolidated line (end_date exclusion + once gate +
        per-line aggregation), find-or-creates the deterministic coupon for
        every per-mode value on the gym's Connect account, attaches the
        coupons to the matching bucket item, and writes each resolved coupon
        (and any ``once`` consumption) back onto the contributing snapshots.

        A no-op when the family carries no snapshots. New lines with no
        stripe_item_id yet are skipped by the planner — they pick up their
        coupon on the next sync once Stripe has assigned the item id.
        """
        if not snapshots:
            return

        current_coupon_ids = await self._current_coupon_ids(
            bucket.existing_sub_id,
            stripe_account_id,
        )
        today = gym_today(parent.timezone)
        plans = plan_line_discounts(
            bucket,
            snapshots,
            current_coupon_ids,
            today,
        )

        items_by_id = {item.stripe_item_id: item for item in bucket.items if item.stripe_item_id}
        for plan in plans:
            await self._apply_line_plan(
                plan,
                items_by_id.get(plan.stripe_item_id),
                stripe_account_id,
                today,
            )

    async def _current_coupon_ids(
        self,
        existing_sub_id: str | None,
        stripe_account_id: str,
    ) -> set[str]:
        """Read the coupon ids currently on the live subscription.

        Empty when there is no existing subscription (a brand-new sub has no
        prior discounts, so every ``once`` snapshot is still pending).
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

    async def _apply_line_plan(
        self,
        plan: LineDiscountPlan,
        item: PaymentsSubscriptionDesiredItem | None,
        stripe_account_id: str,
        today: date,
    ) -> None:
        """Resolve a line's coupons, attach them, and write back.

        Stamps end_date on every ``once`` snapshot the planner found consumed,
        find-or-creates a coupon per surviving per-mode value, attaches them to
        the line item, and writes each value's resolved coupon back onto only
        that value's own contributing snapshots (so a ``once`` value records
        its coupon — the consumption-tracking handle — on the ``once`` rows and
        an ``ongoing`` value on the ``ongoing`` rows).
        """
        for consumed_id in plan.consumed_ids:
            await self._queries.stamp_snapshot_consumed(consumed_id, today)

        coupon_ids: list[str] = []
        for value in plan.values:
            coupon_id = await self._coupons.find_or_create(
                value,
                stripe_account_id,
            )
            coupon_ids.append(coupon_id)
            for applied_discount_id in value.contributing_ids:
                await self._queries.set_snapshot_coupon_id(
                    applied_discount_id,
                    coupon_id,
                )

        if item is not None and coupon_ids:
            item.discounts = [SubscriptionItemDiscount(coupon=cid) for cid in coupon_ids]

    # ── Private Helpers ─────────────────────────────────────────

    async def _build_sync_params(
        self,
        member_id: UUID,
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
    ) -> SyncParams:
        """Resolve parent, family, snapshots, and the desired bucket.

        Pure read-path: this helper runs every query and Stripe account
        lookup needed to build an ``IntervalBucket``, but performs no writes
        to the CRM or Stripe. Shared by ``update_payments_recurring`` (real)
        and ``preview_update_payments_recurring`` (dry run).

        Reads the family's applied-discount snapshots so the sync-time coupon
        step (``_attach_computed_coupons``) can group them per consolidated
        line, find-or-create each line's coupon, attach it, and write the
        resolved stripe_coupon_id back. This helper only shapes the items;
        the coupon computation runs in ``update_payments_recurring`` after
        the freeze step and before ``execute_sync``.
        """
        parent = await self._queries.resolve_parent(member_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )

        family_ids = await self._queries.get_family_ids(parent)

        memberships = await self._queries.get_active_memberships(
            family_ids,
        )

        # Filter cancelled memberships by full identity, not by
        # stripe_price_id — on a shared family plan every row
        # shares the same price, so price-only filtering would
        # drop every sibling when one child cancels.
        cancel_keys = {(item.member_id, item.plan_id) for item in cancel_ids}
        memberships = [m for m in memberships if (m.member_id, m.plan_id) not in cancel_keys]

        # Read the family's applied-discount snapshots for the sync-time
        # coupon computation (owned by the payment_sync phase).
        snapshots = await self._queries.get_applied_discounts(family_ids)

        add_intervals = await self._resolve_add_intervals(add_ids)

        desired = build_desired_items(memberships, add_intervals)
        bucket = build_subscription_bucket(desired, parent.stripe_sub_id_month)

        return SyncParams(
            bucket=bucket,
            parent=parent,
            stripe_account_id=stripe_account_id,
            snapshots=snapshots,
        )

    @staticmethod
    def _validate_freeze_params(
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
        freeze_end_date: date | None,
        unfreeze: bool,
    ) -> None:
        """Ensure freeze/unfreeze is not combined with membership changes."""
        has_membership_changes = bool(add_ids or cancel_ids)
        has_freeze_action = freeze_end_date is not None or unfreeze

        if has_membership_changes and has_freeze_action:
            raise ValueError("Cannot combine membership changes with freeze/unfreeze")
        if freeze_end_date is not None and unfreeze:
            raise ValueError("Cannot freeze and unfreeze in the same operation")

    async def _resolve_add_intervals(
        self,
        add_ids: list[SyncItem],
    ) -> list[IntervalDesiredItem]:
        """Resolve duration_unit and price for new add_ids.

        Items carry no discounts — the sync-time coupon step (payment_sync
        phase) attaches each consolidated line's coupon after.
        """
        if not add_ids:
            return []
        price_ids = [item.stripe_price_id for item in add_ids]
        interval_map = await self._queries.get_price_intervals(price_ids)
        return map_add_ids_to_intervals(add_ids, interval_map)
