"""Stripe create/update/cancel operations for the payment sync flow."""

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    IntervalBucket,
    ParentProfile,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    SUB_ID_FIELD,
)
from src.member_memberships.service.payment_sync.payment_sync_discount_allocator import (
    INTERVAL_PRIORITY,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUpdateRequest,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)


class PaymentSyncStripe:
    """Handles Stripe subscription create/update/cancel per interval."""

    def __init__(
        self,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._subscriptions = subscription_service

    async def execute_sync(
        self,
        buckets: dict[DurationUnit, IntervalBucket],
        parent: ParentProfile,
        stripe_account_id: str,
    ) -> dict[DurationUnit, PaymentsSubscriptionResponse | None]:
        """Create, update, or cancel subscriptions per interval.

        Returns a mapping of interval -> subscription response
        (or None if cancelled).
        """
        results: dict[DurationUnit, PaymentsSubscriptionResponse | None] = {}

        for interval in INTERVAL_PRIORITY:
            bucket = buckets.get(interval)
            existing_sub_id = getattr(parent, SUB_ID_FIELD[interval])

            if bucket and bucket.items:
                resp = await self._sync_bucket(
                    bucket,
                    existing_sub_id,
                    parent.stripe_customer_id,
                    stripe_account_id,
                )
                results[interval] = resp
            elif existing_sub_id:
                await self._cancel_empty(
                    existing_sub_id,
                    stripe_account_id,
                )
                results[interval] = None

        return results

    async def _sync_bucket(
        self,
        bucket: IntervalBucket,
        existing_sub_id: str | None,
        stripe_customer_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Create or update a single interval's subscription."""
        if existing_sub_id:
            return await self._subscriptions.update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=existing_sub_id,
                    stripe_customer_id=stripe_customer_id,
                    items=bucket.items,
                    subscription_discounts=bucket.subscription_discounts,
                ),
                stripe_account_id,
            )

        return await self._subscriptions.create_subscription(
            PaymentsSubscriptionCreateRequest(
                stripe_customer_id=stripe_customer_id,
                items=bucket.items,
                subscription_discounts=bucket.subscription_discounts,
            ),
            stripe_account_id,
        )

    async def _cancel_empty(
        self,
        stripe_subscription_id: str,
        stripe_account_id: str,
    ) -> None:
        """Cancel a subscription that no longer has items."""
        await self._subscriptions.cancel_subscription(
            PaymentsSubscriptionCancelRequest(
                stripe_subscription_id=stripe_subscription_id,
            ),
            stripe_account_id,
        )
