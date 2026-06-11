"""Sync a member's freeze state (pause_collection) to Stripe from the DB."""

from datetime import date
from uuid import UUID

from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionFreezeRequest,
    PaymentsSubscriptionUnfreezeRequest,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.payer_profile import PayerProfile


class PaymentSyncFreeze:
    """Converges Stripe pause_collection to a parent's DB freeze window.

    DB-first and minimal: the freeze window is written to the DB elsewhere (the
    freeze/unfreeze request handler); this service takes the already-resolved
    parent and syncs Stripe to it. Standalone + DI-injectable — the dedicated
    freeze/unfreeze request resolves the parent then calls this directly, and
    the membership sync calls it for its maintenance re-apply with the parent it
    already resolved (no extra read).

    Idempotent (re-freezing updates the resume date; unfreezing a non-paused
    subscription is a Stripe no-op); lets ``PaymentsResourceNotFoundError``
    propagate — a missing subscription when the CRM expects billing is an
    out-of-sync state that must surface.
    """

    def __init__(
        self,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._subscriptions = subscription_service

    async def sync_freeze_state(
        self,
        parent: PayerProfile,
        stripe_account_id: str,
        *,
        idempotency_key: UUID,
    ) -> bool:
        """Converge Stripe to the parent's DB freeze window.

        Frozen in the DB (``parent.is_frozen``) → pause collection; otherwise →
        resume. No-op (returns the DB state) when there is no subscription to
        act on.

        Args:
            parent: The paying parent, carrying the DB freeze window + sub id.
            stripe_account_id: The gym's Stripe Connect account ID.
            idempotency_key: Base key for the Stripe op.

        Returns:
            The resulting frozen state (``True`` frozen, ``False`` unfrozen).
        """
        sub_id = parent.stripe_sub_id_month
        if not sub_id:
            return parent.is_frozen

        if parent.is_frozen:
            await self._freeze(
                sub_id,
                parent.freeze_end_date,
                stripe_account_id,
                idempotency_key=idempotency_key,
            )
            return True
        await self._unfreeze(
            sub_id,
            stripe_account_id,
            idempotency_key=idempotency_key,
        )
        return False

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
