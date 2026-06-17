"""Stripe create/update/cancel operations for the payment sync flow."""

from typing import Literal
from uuid import UUID, uuid4

from src.payments.schema.metadata.stripe_subscription_metadata import (
    StripeSubscriptionMetadata,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
    PreviewInvoice,
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
from src.shared.payer_profile import PayerProfile
from src.sync.sync_schema import (
    IntervalBucket,
)


class PaymentSyncStripe:
    """Handles Stripe subscription create/update/cancel for the sync flow."""

    def __init__(
        self,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._subscriptions = subscription_service

    # ── Subscription Sync ──────────────────────────────────────

    async def execute_sync(
        self,
        bucket: IntervalBucket,
        payer: PayerProfile,
        stripe_account_id: str,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> PaymentsSubscriptionResponse | None:
        """Create, update, or cancel the monthly subscription.

        Args:
            bucket: Desired subscription state.
            payer: The payer profile (customer + metadata source).
            stripe_account_id: The gym's Stripe Connect account ID.
            idempotency_key: Base key for Stripe. Sub-operation keys
                are derived from it (``:sub_create``, ``:sub_update``,
                ``:sub_cancel``).
            pay_first_invoice_out_of_band: The cash flag. On a new
                subscription (no existing sub id on the bucket), mark
                its first invoice as paid out of band instead of
                charging the customer's default payment method. On an
                update it does NOT pay anything out of band, but it is
                still threaded through: it suppresses the card path's
                ``error_if_incomplete`` so a cash family's open proration
                invoice can be settled out of band later (mark-paid-cash).

        Returns:
            Subscription response if created/updated, None if cancelled.
        """
        if bucket.items:
            return await self._sync_bucket(
                bucket,
                payer,
                stripe_account_id,
                idempotency_key=idempotency_key,
                pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
                proration_behavior=proration_behavior,
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
        payer: PayerProfile,
        stripe_account_id: str,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> DueNowVsRecurringPreview | None:
        """Preview the sync as a due-now / recurring split.

        Always returns both halves. ``recurring`` is the steady-state
        preview (``proration_behavior=none``); ``due_now`` is the
        immediate ``always_invoice`` preview when prorating, otherwise
        the same as ``recurring`` — nothing extra is charged now.
        Returns ``None`` for a pure cancellation / no-op (empty bucket),
        which has no upcoming invoice.

        Args:
            bucket: Desired subscription state.
            payer: The payer profile (customer + metadata source).
            stripe_account_id: The gym's Stripe Connect account ID.
            proration_behavior: ``always_invoice`` to also fetch the
                immediate (prorated) ``due_now`` invoice; ``none`` to
                reuse the recurring preview as ``due_now``.

        Returns:
            The due-now / recurring split, or ``None`` if the sync would
            cancel the subscription.
        """
        if not bucket.items:
            return None

        recurring = await self._run_preview(
            bucket, payer, stripe_account_id, "none"
        )
        if proration_behavior == "always_invoice":
            due_now = await self._run_preview(
                bucket, payer, stripe_account_id, "always_invoice"
            )
        else:
            due_now = recurring
        return DueNowVsRecurringPreview(
            due_now=due_now,
            recurring=recurring,
        )

    async def _run_preview(
        self,
        bucket: IntervalBucket,
        payer: PayerProfile,
        stripe_account_id: str,
        proration_behavior: Literal["none", "always_invoice"],
    ) -> PreviewInvoice:
        """One Stripe invoice preview at a given proration behavior.

        Mirrors ``execute_sync`` dispatch: ``preview_update_subscription``
        for an existing sub, ``preview_create_subscription`` for a new
        one. Preview calls do not write to Stripe, so the idempotency
        key is a throwaway only used to satisfy the request schema.
        """
        placeholder_key = str(uuid4())
        metadata = StripeSubscriptionMetadata(
            member_id=payer.member_id,
            gym_id=payer.gym_id,
        )
        if bucket.existing_sub_id:
            return await self._subscriptions.preview_update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                    stripe_customer_id=payer.stripe_customer_id,
                    items=bucket.items,
                    proration_behavior=proration_behavior,
                    metadata=metadata,
                    idempotency_key=placeholder_key,
                    gym_timezone=payer.timezone,
                ),
                stripe_account_id,
            )

        return await self._subscriptions.preview_create_subscription(
            PaymentsSubscriptionCreateRequest(
                stripe_customer_id=payer.stripe_customer_id,
                items=bucket.items,
                proration_behavior=proration_behavior,
                metadata=metadata,
                idempotency_key=placeholder_key,
                gym_timezone=payer.timezone,
            ),
            stripe_account_id,
        )

    # ── Private Helpers ────────────────────────────────────────

    async def _sync_bucket(
        self,
        bucket: IntervalBucket,
        payer: PayerProfile,
        stripe_account_id: str,
        *,
        idempotency_key: UUID,
        pay_first_invoice_out_of_band: bool = False,
        proration_behavior: Literal["none", "always_invoice"] = "none",
    ) -> PaymentsSubscriptionResponse:
        """Create or update the subscription for this bucket.

        ``pay_first_invoice_out_of_band`` (the cash flag) is threaded to
        BOTH branches. On **create** it drives the out-of-band first-invoice
        pay. On **update** it is the card-vs-cash signal for the proration
        charge: a card update (False) is sent ``error_if_incomplete`` so a
        declined proration fails + rolls back; a cash update (True) is NOT,
        so its open proration invoice can be settled out of band later
        (mark-paid-cash). The update itself never pays the proration invoice
        out of band here — only the create's first invoice does.
        """
        metadata = StripeSubscriptionMetadata(
            member_id=payer.member_id,
            gym_id=payer.gym_id,
        )
        if bucket.existing_sub_id:
            return await self._subscriptions.update_subscription(
                PaymentsSubscriptionUpdateRequest(
                    stripe_subscription_id=bucket.existing_sub_id,
                    stripe_customer_id=payer.stripe_customer_id,
                    items=bucket.items,
                    pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
                    proration_behavior=proration_behavior,
                    metadata=metadata,
                    idempotency_key=f"{idempotency_key}:sub_update",
                    gym_timezone=payer.timezone,
                ),
                stripe_account_id,
            )

        return await self._subscriptions.create_subscription(
            PaymentsSubscriptionCreateRequest(
                stripe_customer_id=payer.stripe_customer_id,
                items=bucket.items,
                pay_first_invoice_out_of_band=pay_first_invoice_out_of_band,
                proration_behavior=proration_behavior,
                metadata=metadata,
                idempotency_key=f"{idempotency_key}:sub_create",
                gym_timezone=payer.timezone,
            ),
            stripe_account_id,
        )
