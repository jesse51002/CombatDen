"""Stripe create/update/cancel/freeze operations for the payment sync flow."""

from datetime import date

from src.member_memberships.schema.payment_sync_schema import (
    IntervalBucket,
    ParentProfile,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionFreezeRequest,
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUnfreezeRequest,
    PaymentsSubscriptionUpdateRequest,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)


class PaymentSyncStripe:
    """Handles Stripe subscription create/update/cancel and freeze sync."""

    def __init__(
        self,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._subscriptions = subscription_service

    # ── Subscription Sync ──────────────────────────────────────

    async def execute_sync(
        self,
        bucket: IntervalBucket,
        stripe_customer_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse | None:
        """Create, update, or cancel the monthly subscription.

        Returns:
            Subscription response if created/updated, None if cancelled.
        """
        if bucket.items:
            return await self._sync_bucket(
                bucket,
                stripe_customer_id,
                stripe_account_id,
            )

        if bucket.existing_sub_id:
            await self._subscriptions.cancel_subscription(
                PaymentsSubscriptionCancelRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                ),
                stripe_account_id,
            )

        return None

    # ── Freeze Sync ────────────────────────────────────────────

    async def sync_freeze_state(
        self,
        stripe_sub_id: str | None,
        parent: ParentProfile,
        stripe_account_id: str,
        freeze_end_date: date | None = None,
        unfreeze: bool = False,
    ) -> None:
        """Apply or remove pause_collection on the subscription.

        When explicit params are passed, they take precedence.
        Otherwise falls back to the parent profile's intrinsic
        freeze state (``is_frozen``).

        Idempotent: freezing an already-frozen subscription updates
        the resumes_at date; unfreezing a non-paused subscription
        is a no-op on Stripe's side.

        Lets PaymentsResourceNotFoundError propagate — a missing
        subscription during freeze sync means the CRM expects
        billing to resume but Stripe has no subscription. This is
        an out-of-sync state that must surface.

        Args:
            stripe_sub_id: The subscription to freeze/unfreeze.
                No-op if None.
            parent: Parent profile with intrinsic freeze dates.
            stripe_account_id: The gym's Stripe Connect account ID.
            freeze_end_date: Explicit freeze request with end date.
            unfreeze: Explicit unfreeze request.
        """
        if not stripe_sub_id:
            return

        if freeze_end_date is not None:
            await self._freeze(stripe_sub_id, freeze_end_date, stripe_account_id)
        elif unfreeze:
            await self._unfreeze(stripe_sub_id, stripe_account_id)
        elif parent.is_frozen:
            await self._freeze(
                stripe_sub_id,
                parent.freeze_end_date,
                stripe_account_id,
            )
        else:
            await self._unfreeze(stripe_sub_id, stripe_account_id)

    async def _freeze(
        self,
        stripe_sub_id: str,
        freeze_end_date: date | None,
        stripe_account_id: str,
    ) -> None:
        """Pause collection on a subscription."""
        await self._subscriptions.freeze_subscription(
            PaymentsSubscriptionFreezeRequest(
                stripe_subscription_id=stripe_sub_id,
                freeze_end_date=freeze_end_date,
            ),
            stripe_account_id,
        )

    async def _unfreeze(
        self,
        stripe_sub_id: str,
        stripe_account_id: str,
    ) -> None:
        """Resume collection on a subscription."""
        await self._subscriptions.unfreeze_subscription(
            PaymentsSubscriptionUnfreezeRequest(
                stripe_subscription_id=stripe_sub_id,
            ),
            stripe_account_id,
        )

    # ── Private Helpers ────────────────────────────────────────

    async def _sync_bucket(
        self,
        bucket: IntervalBucket,
        stripe_customer_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Create or update the subscription for this bucket."""
        if bucket.existing_sub_id:
            return await self._subscriptions.update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
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
