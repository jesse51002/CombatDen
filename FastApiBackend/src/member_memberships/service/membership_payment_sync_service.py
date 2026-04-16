"""Service for syncing membership payment state with Stripe."""

from __future__ import annotations

import logging
from datetime import date
from uuid import UUID

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    IntervalDesiredItem,
    ParentProfile,
    SyncItem,
)
from src.member_memberships.service.linked_member_discount_service import (
    LinkedMemberDiscountService,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    aggregate_plan_discounts,
    build_desired_items,
    build_subscription_bucket,
    map_add_ids_to_intervals,
)
from src.member_memberships.service.payment_sync.payment_sync_discount_allocator import (
    allocate_linked_discounts,
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
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService

logger = logging.getLogger(__name__)


class MembershipPaymentSyncService:
    """Syncs membership payment state with Stripe.

    Orchestrates sub-services to resolve linked accounts,
    build the desired subscription state, allocate linked
    discounts, and create/update/cancel the Stripe subscription.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        subscription_service: PaymentsStripeSubscriptionService,
        gym_stripe_service: GymStripeService,
        linked_discount_service: LinkedMemberDiscountService,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._stripe = PaymentSyncStripe(subscription_service)
        self._gym_stripe = gym_stripe_service
        self._linked_discounts = linked_discount_service
        self._price_writeback = PriceWriteback(
            db_pool=db_pool,
            subscription_service=subscription_service,
        )

    async def update_payments_recurring(
        self,
        crm_user_id: UUID,
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
        freeze_end_date: date | None = None,
        unfreeze: bool = False,
        pay_first_invoice_out_of_band: bool = False,
    ) -> PaymentsSubscriptionResponse | None:
        """Sync a member's recurring memberships with Stripe.

        Resolves to the paying parent account, applies any
        freeze/unfreeze action first, then gathers all family
        memberships, recalculates linked discounts, and
        reconciles the monthly Stripe subscription.

        Explicit freeze/unfreeze cannot be combined with
        membership changes — billing order matters on Stripe,
        so these must be separate operations.

        Args:
            crm_user_id: Any family member's profile ID.
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

        parent = await self._queries.resolve_parent(crm_user_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )

        # ── Freeze/unfreeze first ─────────────────────────
        await self._stripe.sync_freeze_state(
            parent.stripe_sub_id_month,
            parent,
            stripe_account_id,
            freeze_end_date=freeze_end_date,
            unfreeze=unfreeze,
        )

        # ── Full membership sync ──────────────────────────
        family_ids = await self._queries.get_family_ids(parent)
        children_ids = [fid for fid in family_ids if fid != parent.crm_user_id]

        # ── Linked discount recalculation ──────────────────
        include = [item.to_membership_info() for item in add_ids] or None
        exclude = [item.to_membership_info() for item in cancel_ids] or None
        members, discount_ids = await self._linked_discounts.calculate_linked_discount_ids(
            parent_id=parent.crm_user_id,
            children_ids=children_ids,
            gym_id=parent.gym_id,
            include_memberships=include,
            exclude_memberships=exclude,
        )

        # ── Build desired items for Stripe ─────────────────
        memberships = await self._queries.get_active_memberships(
            family_ids,
        )

        # Filter cancelled memberships by full identity, not by
        # stripe_price_id — on a shared family plan every row
        # shares the same price, so price-only filtering would
        # drop every sibling when one child cancels.
        cancel_keys = {(item.crm_user_id, item.plan_id) for item in cancel_ids}
        memberships = [m for m in memberships if (m.crm_user_id, m.plan_id) not in cancel_keys]

        # Resolve every discount referenced by this sync — linked,
        # plan-level, and newly-added — in one batched query. CRM
        # UUIDs must be translated to real Stripe coupon IDs before
        # hitting Stripe. Add-item discounts are folded in here so
        # they can be attached to the new items on the first pass
        # (no dependency on the filtered-view writeback race).
        linked_ids = {d for d in discount_ids if d is not None}
        plan_discount_ids: set[UUID] = {d for m in memberships for d in m.discount_ids}
        add_discount_ids: set[UUID] = {d for item in add_ids for d in item.discount_ids}
        all_discount_ids = sorted(linked_ids | plan_discount_ids | add_discount_ids)
        details = (
            await self._queries.get_discount_details(all_discount_ids) if all_discount_ids else []
        )
        discounts = [d for d in details if d.discount_id in linked_ids]
        coupon_by_discount_id: dict[UUID, str] = {
            d.discount_id: d.stripe_coupon_id for d in details
        }

        add_intervals = await self._resolve_add_intervals(
            add_ids,
            coupon_by_discount_id,
        )

        plan_discounts = aggregate_plan_discounts(
            memberships,
            coupon_by_discount_id,
        )
        desired = build_desired_items(
            memberships,
            add_intervals,
            plan_discounts,
        )

        bucket = build_subscription_bucket(desired, parent.stripe_sub_id_month)
        allocate_linked_discounts(bucket, discounts)

        sub_result = await self._stripe.execute_sync(
            bucket,
            parent.stripe_customer_id,
            stripe_account_id,
            pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
        )

        # ── Write back subscription ID ─────────────────────
        new_sub_id = sub_result.stripe_subscription_id if sub_result else None
        await self._queries.update_profile_sub_id(
            parent.crm_user_id,
            new_sub_id,
        )

        # ── Persist linked discount assignments ────────────
        await self._linked_discounts.persist_assignments(
            members,
            discount_ids,
            parent.gym_id,
        )

        # ── Mirror post-discount totals back onto CRM ──────
        await self._price_writeback.sync_prices_from_stripe(
            parent_crm_user_id=parent.crm_user_id,
            gym_id=parent.gym_id,
            stripe_sub_id=new_sub_id,
            stripe_account_id=stripe_account_id,
        )

        return sub_result

    async def bulk_payment_sync(
        self,
        crm_user_ids: list[UUID],
    ) -> None:
        """Re-sync payment state for multiple members.

        Args:
            crm_user_ids: Members whose memberships need sync.
        """
        for crm_user_id in crm_user_ids:
            try:
                await self.update_payments_recurring(
                    crm_user_id,
                    add_ids=[],
                    cancel_ids=[],
                )
            except PaymentsResourceNotFoundError:
                logger.error(
                    "Stripe resource not found during payment sync for %s",
                    crm_user_id,
                    exc_info=True,
                )
            except Exception:
                logger.error(
                    "Payment sync failed for %s",
                    crm_user_id,
                    exc_info=True,
                )

    async def resolve_parent(self, crm_user_id: UUID) -> ParentProfile:
        """Expose parent resolution for upstream validation.

        Args:
            crm_user_id: Any family member's profile ID.

        Returns:
            The paying parent's profile.
        """
        return await self._queries.resolve_parent(crm_user_id)

    # ── Private Helpers ─────────────────────────────────────────

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
        coupon_by_discount_id: dict[UUID, str],
    ) -> list[IntervalDesiredItem]:
        """Resolve duration_unit, price, and discounts for new add_ids.

        Takes enriched ``SyncItem`` directly (not the stripped
        desired-item) so each item's ``discount_ids`` can be
        resolved to Stripe coupons on the first pass.
        """
        if not add_ids:
            return []
        price_ids = [item.stripe_price_id for item in add_ids]
        interval_map = await self._queries.get_price_intervals(price_ids)
        return map_add_ids_to_intervals(
            add_ids,
            interval_map,
            coupon_by_discount_id,
        )
