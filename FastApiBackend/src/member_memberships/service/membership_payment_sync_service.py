"""Service for syncing membership payment state with Stripe."""

import logging
from uuid import UUID

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    IntervalDesiredItem,
    LinkedDiscountInfo,
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
from src.shared.stripe_reconciliation.stripe_reconciliation_service import (
    StripeReconciliationService,
)

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
        stripe_reconciliation_service: StripeReconciliationService,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._stripe = PaymentSyncStripe(subscription_service)
        self._gym_stripe = gym_stripe_service
        self._reconciliation = stripe_reconciliation_service

    async def update_payments_recurring(
        self,
        crm_user_id: UUID,
        add_ids: list[PaymentsSubscriptionDesiredItem],
        cancel_ids: list[PaymentsSubscriptionDesiredItem],
        linked_discounts: list[UUID] | None = None,
    ) -> list[PaymentsSubscriptionResponse]:
        """Sync a member's recurring memberships with Stripe.

        Resolves to the paying parent account, gathers all
        family memberships, and reconciles Stripe subscriptions
        per billing interval.

        Args:
            crm_user_id: Any family member's profile ID.
            add_ids: New items to add to subscriptions.
            cancel_ids: Items to remove from subscriptions.
            linked_discounts: Explicit discount IDs to use.
                None means query from profiles.

        Returns:
            All resulting subscription responses (one per active
            interval). Cancelled intervals are not included.
        """
        parent = await self._queries.resolve_parent(crm_user_id)
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            parent.gym_id,
        )
        family_ids = await self._queries.get_family_ids(parent)
        memberships = await self._queries.get_active_memberships(family_ids)

        add_intervals = await self._resolve_add_intervals(add_ids)
        plan_discounts = aggregate_plan_discounts(memberships)
        desired = build_desired_items(
            memberships,
            add_intervals,
            cancel_ids,
            plan_discounts,
        )

        discounts = await self._resolve_discounts(
            linked_discounts,
            family_ids,
        )

        buckets = group_by_interval(desired, parent)
        allocate_linked_discounts(buckets, discounts)

        sub_results = await self._stripe.execute_sync(
            buckets,
            parent,
            stripe_account_id,
        )

        await self._write_back_sub_ids(sub_results, parent.crm_user_id)

        return [r for r in sub_results.values() if r is not None]

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
            except PaymentsResourceNotFoundError as exc:
                try:
                    await self._reconciliation.handle_not_found(exc)
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

    async def _resolve_discounts(
        self,
        linked_discounts: list[UUID] | None,
        family_ids: list[UUID],
    ) -> list[LinkedDiscountInfo]:
        """Resolve linked discount UUIDs to their Stripe coupon info.

        If linked_discounts is None, queries from profiles.
        If empty list, returns empty (no discounts).
        """
        if linked_discounts is not None:
            discount_ids = linked_discounts
        else:
            discount_ids = await self._queries.get_linked_discount_ids(
                family_ids,
            )

        if not discount_ids:
            return []
        return await self._queries.get_discount_details(discount_ids)

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
