"""Handler for Stripe ``customer.subscription.deleted`` events.

Stripe fires this when a subscription is canceled -- including when its dunning
engine exhausts retries and cancels on its own schedule. The CRM's push sync
never learns this (it only pushes), so without this handler a Stripe-side
cancellation is only caught by the twice-daily reconciler sweep. This is the
**prompt path**: it absorbs the cancellation into the CRM immediately, reusing
the SAME ``SubscriptionCancellationAbsorber`` the reconciler poll uses -- CRM
only: mark the family's live recurring memberships cancelled + null the parent's
``stripe_sub_id_month``, with no Stripe calls (Stripe already cancelled).

The member is read from the subscription's metadata (our sync stamps
``member_id`` = the paying parent). Idempotent: the absorber is a no-op once the
family is already cancelled, and the dispatcher's event-log dedup guards
re-delivery. The absorber runs on its own DB pool (like the once-discount
settle), so the unused ``session`` here is only the dispatcher's interface.
"""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from src.member_memberships.service.memberships.member_memberships_cancel_absorber import (
    SubscriptionCancellationAbsorber,
)

logger = logging.getLogger(__name__)

EVENT_TYPE = "customer.subscription.deleted"


class CustomerSubscriptionDeletedHandler:
    """Absorb a Stripe-cancelled subscription into the CRM (prompt path)."""

    def __init__(
        self,
        cancellation_absorber: SubscriptionCancellationAbsorber,
    ) -> None:
        self._absorber = cancellation_absorber

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
                "member_id in metadata (gym_id=%s); cannot absorb",
                subscription.get("id"),
                gym_id,
            )
            return

        cancelled = await self._absorber.absorb(UUID(member_id_str))
        logger.info(
            "customer.subscription.deleted: absorbed sub %s for member %s "
            "(gym_id=%s); %d membership(s) cancelled",
            subscription.get("id"),
            member_id_str,
            gym_id,
            cancelled,
        )
