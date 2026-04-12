"""Stripe reconciliation service for cleaning up stale CRM linkages.

When Stripe reports a resource as not-found or inactive, this service
looks up the affected CRM record by Stripe resource ID and delegates
to the appropriate CRM-level service for cleanup.

This service never calls Stripe directly — it only operates on CRM
data. Each Stripe resource type has (or will have) a corresponding
CRM-level service that mirrors the Stripe service hierarchy:

    Stripe Service                  →  CRM Service
    ─────────────────────────────      ──────────────────────────
    PaymentsStripeMembersService    →  MembersManagementService
    PaymentsStripeSubscriptionSvc   →  (TODO: CRM subscription svc)
    PaymentsStripePriceService      →  (TODO: CRM price service)
    PaymentsStripeMembershipService →  (TODO: CRM membership plan svc)
    PaymentsStripeDiscountService   →  (TODO: CRM discount service)
"""

import logging
from uuid import UUID

from sqlalchemy import text

from src.members.service.members_management_service import (
    MembersManagementService,
)
from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.stripe_reconciliation import SQL_DIR

logger = logging.getLogger(__name__)


class StripeReconciliationService:
    """Reconciles CRM state when Stripe resources are not found.

    Receives PaymentsResourceNotFoundError, looks up the affected CRM
    record by the Stripe resource ID stored in the exception, and
    dispatches to the appropriate CRM-level cleanup function.

    Inactive resources are not handled here — the Stripe services
    automatically reactivate archived prices/products when a gym owner
    tries to use them (write operations).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        members_management_service: MembersManagementService,
    ) -> None:
        self._db_pool = db_pool
        self._members_management = members_management_service

    # ── public dispatch ─────────────────────────────────────────

    async def handle_not_found(
        self,
        exc: PaymentsResourceNotFoundError,
    ) -> None:
        """Reconcile CRM state when a Stripe resource is not found.

        Dispatches to the appropriate CRM-level cleanup based on
        the resource type in the exception.

        Args:
            exc: The not-found error with resource_id and
                resource_type identifying the missing Stripe resource.
        """
        match exc.resource_type:
            case StripeResourceType.customer:
                await self._handle_customer_not_found(exc.resource_id)

            case StripeResourceType.subscription:
                # TODO: Build a CRM subscription service
                # (e.g. CrmSubscriptionService) that mirrors
                # PaymentsStripeSubscriptionService.
                #
                # When a Stripe subscription is not found:
                # 1. Look up member_memberships by stripe_item_id
                #    (the Stripe subscription ID stored on each
                #    membership row) to find the crm_user_id.
                # 2. Use MemberMembershipsService.cancel_recurring(
                #    crm_user_id) to cancel all active recurring
                #    memberships at their next_due_date (end of
                #    current billing period). Falls back to today
                #    if next_due_date is NULL or in the past.
                # 3. Clear stripe_sub_id_month on user_gym_profiles
                #    for that member.
                # 4. The Stripe subscription is already gone, so
                #    no Stripe API call is needed.
                pass

            case StripeResourceType.price:
                # TODO: Build a CRM price service
                # (e.g. CrmPriceService) that mirrors
                # PaymentsStripePriceService.
                #
                # When a Stripe price is not found:
                # 1. Look up membership_plan_prices by
                #    stripe_price_id to find the affected
                #    CRM price record.
                # 2. Deactivate the price: set is_active = false
                #    on membership_plan_prices.
                # 3. Any active memberships using this price_id
                #    in member_memberships may need repricing —
                #    the MembershipPricingService already handles
                #    recalculation, but the trigger for it needs
                #    to be wired up here.
                # 4. No Stripe API call needed — the price is
                #    already gone.
                pass

            case StripeResourceType.product:
                # TODO: Build a CRM membership plan service
                # (e.g. CrmMembershipPlanService) that mirrors
                # PaymentsStripeMembershipService.
                #
                # When a Stripe product is not found:
                # 1. Look up membership_plans by stripe_product_id
                #    to find the affected plan.
                # 2. Deactivate the plan (add an is_active flag
                #    or equivalent — the plan should no longer be
                #    assignable to new members).
                # 3. Cancel all active recurring memberships on this
                #    plan at their next_due_date. Sets cancel_date
                #    and end_date to GREATEST(COALESCE(next_due_date,
                #    today), today) — the underlying Stripe product
                #    is gone so the memberships can't bill past the
                #    current period.
                # 4. No Stripe API call needed.
                pass

            case StripeResourceType.subscription_item:
                # TODO: Build a CRM subscription item service
                # (When a Stripe price is not found:
                # 1. Look up membership_plan_prices by
                #    stripe_price_id to find the affected
                #    CRM price record.
                # 2. Deactivate the price: set is_active = false
                #    on membership_plan_prices.
                # 3. Any active memberships using this price_id
                #    in member_memberships may need repricing —
                #    the MembershipPricingService already handles
                #    recalculation, but the trigger for it needs
                #    to be wired up here.
                # 4. No Stripe API call needed — the price is
                #    already gone.e.g. CrmSubscriptionItemService) that mirrors
                # PaymentsSubscriptionItem.
                #
                # When a Stripe subscription item is not found:
                # 1. Look up member_memberships by stripe_item_id (the
                #    parent subscription ID) and the price_id linked
                #    to this item to find the specific membership row.
                # 2. Cancel the affected membership at next_due_date
                #    — sets cancel_date and end_date to
                #    GREATEST(COALESCE(next_due_date, today), today).
                #    The subscription item is gone so that membership
                #    slot can't bill past the current period.
                # 3. If the parent subscription still exists but
                #    this item was removed, the membership should
                #    still be cancelled on the CRM side since the
                #    billing line item no longer exists.
                # 4. No Stripe API call needed — the item is
                #    already gone.
                pass

            case StripeResourceType.coupon:
                # TODO: Build a CRM discount service
                # (e.g. CrmDiscountService) that mirrors
                # PaymentsStripeDiscountService.
                #
                # When a Stripe coupon is not found:
                # 1. Look up discount linkages — discount_ids in
                #    member_memberships is a JSONB array of UUIDs
                #    referencing a discounts table. The discounts
                #    table stores the stripe coupon ID.
                # 2. Find the CRM discount record by its Stripe
                #    coupon ID, then remove that discount UUID
                #    from the discount_ids array on every
                #    member_memberships row that references it.
                # 3. Memberships that had this coupon will need
                #    repricing since the discount no longer applies.
                # 4. No Stripe API call needed.
                pass

    # NOTE: Inactive resources are handled at the Stripe service
    # level, not here. When a gym owner tries to use an archived
    # price or product, PaymentsStripePriceService.validate_price_active
    # automatically reactivates it on Stripe (sets active=True)
    # before proceeding. This is the correct behavior because
    # inactive resources are only encountered during write
    # operations where the owner explicitly wants to use them.

    # ── private helpers ─────────────────────────────────────────

    async def _find_member_by_stripe_customer(
        self,
        stripe_customer_id: str,
    ) -> UUID | None:
        """Look up a CRM member by their Stripe customer ID.

        Args:
            stripe_customer_id: The Stripe customer ID to search for.

        Returns:
            The crm_user_id if found, None otherwise.
        """
        sql = load_sql(
            SQL_DIR / "find_member_by_customer.sql",
        )

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"stripe_customer_id": stripe_customer_id},
            )
            row = result.mappings().fetchone()

        if not row:
            return None
        return UUID(str(row["crm_user_id"]))

    async def _handle_customer_not_found(
        self,
        stripe_customer_id: str | None,
    ) -> None:
        """Handle a missing Stripe customer by unlinking payment.

        Looks up the member by stripe_customer_id, then calls
        MembersManagementService.unlink_payment to clear card
        fields.

        Args:
            stripe_customer_id: The Stripe customer ID that was
                not found.
        """
        if not stripe_customer_id:
            logger.warning(
                "Cannot reconcile customer not-found: no resource_id in exception",
            )
            return

        crm_user_id = await self._find_member_by_stripe_customer(
            stripe_customer_id,
        )

        if not crm_user_id:
            logger.warning(
                "Cannot reconcile customer not-found: no CRM member with stripe_customer_id=%s",
                stripe_customer_id,
            )
            return

        await self._members_management.unlink_payment(crm_user_id)
