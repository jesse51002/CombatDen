"""Handler for Stripe ``customer.subscription.deleted`` events.

Stripe fires this when a subscription is canceled -- including when its dunning
engine exhausts retries and cancels on its own schedule. The CRM's push sync
never learns this on its own (it only pushes), so without this handler a
Stripe-side cancellation is caught only by the twice-daily reconciler sweep. This
is the **prompt path**: it runs a payment sync for the member's family right away,
and the sync, finding the subscription gone, records the cancellation in the CRM
(cancels the family's live recurring memberships + nulls the parent's sub id).

The member is read from the subscription's metadata (our sync stamps
``member_id`` = the paying parent). ``bulk_payment_sync`` locks the family, runs
the sync, and swallows its own per-member failures, so a transient error never
fails the webhook. Idempotent: re-running the sync on an already-cancelled family
syncs to nothing, and the dispatcher's event-log dedup guards re-delivery. The
unused ``session`` is only the dispatcher's interface — the sync owns its own DB
pool + family lock.
"""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from src.member_memberships.service.payment_sync.payment_sync_service import (
    PaymentSyncService,
)

logger = logging.getLogger(__name__)

EVENT_TYPE = "customer.subscription.deleted"


class CustomerSubscriptionDeletedHandler:
    """Sync a family on a Stripe-cancelled subscription (prompt path)."""

    def __init__(self, payment_sync_service: PaymentSyncService) -> None:
        self._payment_sync = payment_sync_service

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        subscription = event["data"]["object"]
        metadata = subscription.get("metadata") or {}
        member_id_str = metadata.get("member_id")
        if not member_id_str:
            logger.warning(
                "customer.subscription.deleted: subscription %s has no "
                "member_id in metadata (gym_id=%s); cannot sync",
                subscription.get("id"),
                gym_id,
            )
            return

        try:
            member_id = UUID(member_id_str)
        except ValueError:
            logger.warning(
                "customer.subscription.deleted: subscription %s has a "
                "malformed member_id %r in metadata (gym_id=%s); cannot sync",
                subscription.get("id"),
                member_id_str,
                gym_id,
            )
            return

        await self._payment_sync.bulk_payment_sync([member_id])
        logger.info(
            "customer.subscription.deleted: synced family of member %s "
            "(gym_id=%s) to record the cancellation",
            member_id_str,
            gym_id,
        )
