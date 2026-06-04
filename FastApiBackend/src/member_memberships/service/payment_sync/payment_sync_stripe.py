"""Stripe create/update/cancel/freeze operations for the payment sync flow."""

from datetime import date
from typing import Literal
from uuid import UUID, uuid4

from src.member_memberships.schema.payment_sync_schema import (
    IntervalBucket,
    ParentProfile,
)
from src.payments.schema.metadata.stripe_subscription_metadata import (
    StripeSubscriptionMetadata,
)
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
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
        parent: ParentProfile,
        stripe_account_id: str,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
    ) -> PaymentsSubscriptionResponse | None:
        """Create, update, or cancel the monthly subscription.

        Args:
            bucket: Desired subscription state.
            parent: Paying parent profile (customer + metadata source).
            stripe_account_id: The gym's Stripe Connect account ID.
            idempotency_key: Base key for Stripe. Sub-operation keys
                are derived from it (``:sub_create``, ``:sub_update``,
                ``:sub_cancel``).
            pay_first_invoice_out_of_band: When a new subscription
                is being created (no existing sub id on the bucket),
                mark its first invoice as paid out of band instead
                of charging the customer's default payment method.
                Ignored when updating an existing subscription.

        Returns:
            Subscription response if created/updated, None if cancelled.
        """
        if bucket.items:
            return await self._sync_bucket(
                bucket,
                parent,
                stripe_account_id,
                idempotency_key=idempotency_key,
                pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
            )

        if bucket.existing_sub_id:
            await self._subscriptions.cancel_subscription(
                PaymentsSubscriptionCancelRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                    idempotency_key=f"{idempotency_key}:sub_cancel",
                ),
                stripe_account_id,
            )

        return None

    async def preview_execute_sync(
        self,
        bucket: IntervalBucket,
        parent: ParentProfile,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse | None:
        """Preview what ``execute_sync`` would charge, without mutating.

        Mirrors ``execute_sync`` dispatch rules: calls
        ``preview_update_subscription`` when an existing sub will
        be updated, ``preview_create_subscription`` when a new sub
        will be created. Returns ``None`` for pure cancellations
        (empty bucket) and no-op syncs — a cancellation has no
        upcoming invoice.

        Args:
            bucket: Desired subscription state.
            parent: Paying parent profile (customer + metadata source).
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Invoice preview if the sync would create/update a
            subscription; ``None`` if the sync would cancel or
            no-op.
        """
        if not bucket.items:
            return None

        # Preview calls do not write to Stripe, so idempotency_key is
        # unused downstream — supply a throwaway key to satisfy the
        # shared request schema.
        placeholder_key = str(uuid4())
        metadata = StripeSubscriptionMetadata(
            member_id=parent.member_id,
            gym_id=parent.gym_id,
        )
        if bucket.existing_sub_id:
            proration_behavior: Literal["none", "always_invoice"] = (
                "always_invoice" if any(item.prorate for item in bucket.items) else "none"
            )
            return await self._subscriptions.preview_update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                    stripe_customer_id=parent.stripe_customer_id,
                    items=bucket.items,
                    subscription_discounts=bucket.subscription_discounts,
                    proration_behavior=proration_behavior,
                    metadata=metadata,
                    idempotency_key=placeholder_key,
                    gym_timezone=parent.timezone,
                ),
                stripe_account_id,
            )

        return await self._subscriptions.preview_create_subscription(
            PaymentsSubscriptionCreateRequest(
                stripe_customer_id=parent.stripe_customer_id,
                items=bucket.items,
                subscription_discounts=bucket.subscription_discounts,
                metadata=metadata,
                idempotency_key=placeholder_key,
                gym_timezone=parent.timezone,
            ),
            stripe_account_id,
        )

    # ── Freeze Sync ────────────────────────────────────────────

    async def sync_freeze_state(
        self,
        stripe_sub_id: str | None,
        parent: ParentProfile,
        stripe_account_id: str,
        idempotency_key: UUID,
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
            await self._freeze(
                stripe_sub_id,
                freeze_end_date,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )
        elif unfreeze:
            await self._unfreeze(
                stripe_sub_id,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )
        elif parent.is_frozen:
            await self._freeze(
                stripe_sub_id,
                parent.freeze_end_date,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )
        else:
            await self._unfreeze(
                stripe_sub_id,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )

    async def _freeze(
        self,
        stripe_sub_id: str,
        freeze_end_date: date | None,
        stripe_account_id: str,
        *,
        idempotency_key: UUID,
    ) -> None:
        """Pause collection on a subscription."""
        await self._subscriptions.freeze_subscription(
            PaymentsSubscriptionFreezeRequest(
                stripe_subscription_id=stripe_sub_id,
                freeze_end_date=freeze_end_date,
                idempotency_key=f"{idempotency_key}:freeze",
            ),
            stripe_account_id,
        )

    async def _unfreeze(
        self,
        stripe_sub_id: str,
        stripe_account_id: str,
        *,
        idempotency_key: UUID,
    ) -> None:
        """Resume collection on a subscription."""
        await self._subscriptions.unfreeze_subscription(
            PaymentsSubscriptionUnfreezeRequest(
                stripe_subscription_id=stripe_sub_id,
                idempotency_key=f"{idempotency_key}:unfreeze",
            ),
            stripe_account_id,
        )

    # ── Private Helpers ────────────────────────────────────────

    async def _sync_bucket(
        self,
        bucket: IntervalBucket,
        parent: ParentProfile,
        stripe_account_id: str,
        *,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
    ) -> PaymentsSubscriptionResponse:
        """Create or update the subscription for this bucket.

        ``pay_first_invoice_out_of_band`` only applies when a new
        subscription is being created. Updating an existing
        subscription (adding/removing items) does not trigger the
        "first invoice" pattern; any proration charge should be
        handled separately via the mark-paid-cash endpoint.
        """
        metadata = StripeSubscriptionMetadata(
            member_id=parent.member_id,
            gym_id=parent.gym_id,
        )
        if bucket.existing_sub_id:
            # Any item requesting proration (e.g. a mid-cycle price
            # swap with prorate=True) flips the whole update to
            # ``always_invoice`` — Stripe cuts the prorated delta
            # as an immediate invoice rather than deferring it to
            # the next renewal. Existing items always carry
            # prorate=False, so this only fires when the caller
            # explicitly opted into proration on a new/replacement
            # item.
            proration_behavior: Literal["none", "always_invoice"] = (
                "always_invoice" if any(item.prorate for item in bucket.items) else "none"
            )
            return await self._subscriptions.update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                    stripe_customer_id=parent.stripe_customer_id,
                    items=bucket.items,
                    subscription_discounts=bucket.subscription_discounts,
                    proration_behavior=proration_behavior,
                    metadata=metadata,
                    idempotency_key=f"{idempotency_key}:sub_update",
                    gym_timezone=parent.timezone,
                ),
                stripe_account_id,
            )

        return await self._subscriptions.create_subscription(
            PaymentsSubscriptionCreateRequest(
                stripe_customer_id=parent.stripe_customer_id,
                items=bucket.items,
                subscription_discounts=bucket.subscription_discounts,
                pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
                metadata=metadata,
                idempotency_key=f"{idempotency_key}:sub_create",
                gym_timezone=parent.timezone,
            ),
            stripe_account_id,
        )
