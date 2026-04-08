"""Service for syncing membership payment state with Stripe."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401

if TYPE_CHECKING:
    from src.shared.stripe_reconciliation.stripe_reconciliation_service import (
        StripeReconciliationService,
    )
from src.member_memberships.schema.payment_sync_schema import (
    IntervalDesiredItem,
    SyncItem,
)
from src.member_memberships.service.linked_member_discount_service import (
    LinkedMemberDiscountService,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    SUB_ID_FIELD,
    aggregate_plan_discounts,
    build_desired_items,
    group_by_interval,
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
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
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
    group memberships by billing interval, allocate linked
    discounts, and create/update/cancel Stripe subscriptions.
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

    async def update_payments_recurring(
        self,
        crm_user_id: UUID,
        add_ids: list[SyncItem],
        cancel_ids: list[SyncItem],
    ) -> list[PaymentsSubscriptionResponse]:
        """Sync a member's recurring memberships with Stripe.

        Resolves to the paying parent account, gathers all
        family memberships, recalculates linked discounts,
        and reconciles Stripe subscriptions per billing interval.

        Args:
            crm_user_id: Any family member's profile ID.
            add_ids: New items to add to subscriptions.
            cancel_ids: Items to remove from subscriptions.

        Returns:
            All resulting subscription responses (one per active
            interval). Cancelled intervals are not included.
        """
        parent = await self._queries.resolve_parent(crm_user_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )
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

        non_none_ids = [d for d in discount_ids if d is not None]
        discounts = await self._queries.get_discount_details(non_none_ids) if non_none_ids else []

        # ── Build desired items for Stripe ─────────────────
        stripped_add = [item.to_desired_item() for item in add_ids]
        stripped_cancel = [item.to_desired_item() for item in cancel_ids]

        memberships = await self._queries.get_active_memberships(
            family_ids,
        )
        add_intervals = await self._resolve_add_intervals(stripped_add)
        plan_discounts = aggregate_plan_discounts(memberships)
        desired = build_desired_items(
            memberships,
            add_intervals,
            stripped_cancel,
            plan_discounts,
        )

        buckets = group_by_interval(desired, parent)
        allocate_linked_discounts(buckets, discounts)

        sub_results = await self._stripe.execute_sync(
            buckets,
            parent,
            stripe_account_id,
        )

        await self._write_back_sub_ids(sub_results, parent.crm_user_id)

        # ── Persist linked discount assignments ────────────
        await self._linked_discounts.persist_assignments(
            members,
            discount_ids,
            parent.gym_id,
        )

        return [r for r in sub_results.values() if r is not None]

    async def bulk_payment_sync(
        self,
        crm_user_ids: list[UUID],
        reconciliation_service: StripeReconciliationService,
    ) -> None:
        """Re-sync payment state for multiple members.

        Args:
            crm_user_ids: Members whose memberships need sync.
            reconciliation_service: StripeReconciliationService
                for handling not-found errors.
        """
        for crm_user_id in crm_user_ids:
            try:
                await self.update_payments_recurring(
                    crm_user_id,
                    add_ids=[],
                    cancel_ids=[],
                )
            except PaymentsResourceNotFoundError as exc:
                try:
                    await reconciliation_service.handle_not_found(
                        exc,
                    )
                except Exception:
                    logger.error(
                        "Reconciliation failed for %s",
                        crm_user_id,
                        exc_info=True,
                    )
            except Exception:
                logger.error(
                    "Payment sync failed for %s",
                    crm_user_id,
                    exc_info=True,
                )

    # ── Private Helpers ─────────────────────────────────────────

    async def _resolve_add_intervals(
        self,
        add_ids: list[PaymentsSubscriptionDesiredItem],
    ) -> list[IntervalDesiredItem]:
        """Resolve duration_unit and price for new add_ids items."""
        if not add_ids:
            return []
        price_ids = [item.stripe_price_id for item in add_ids]
        interval_map = await self._queries.get_price_intervals(price_ids)
        return map_add_ids_to_intervals(add_ids, interval_map)

    async def _write_back_sub_ids(
        self,
        sub_results: dict[DurationUnit, PaymentsSubscriptionResponse | None],
        crm_user_id: UUID,
    ) -> None:
        """Write Stripe subscription IDs back to the parent profile."""
        if not sub_results:
            return

        updates = {
            SUB_ID_FIELD[interval]: (resp.stripe_subscription_id if resp else None)
            for interval, resp in sub_results.items()
        }
        await self._queries.update_profile_sub_ids(crm_user_id, updates)
