"""Membership reprice: cancel-old + insert-successor-at-new-price + verify-or-revert.

Standalone op — no tasks import. Uses MemberMembershipsTransitionBase for the shared
transition machinery; this file adds same-plan price resolution and reprice validation.
"""

from uuid import UUID, uuid5

from schema.membership_plan import PlanType
from schema.task import ProrationBehavior

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_transition_base import (
    MemberMembershipsTransitionBase,
)
from src.shared.db_first_helpers import sync_or_revert
from src.shared.gym_timezone import gym_today

# Namespace for uuid5(REPRICE_IDEMPOTENCY_NAMESPACE, successor_item_id) —
# stable Stripe idempotency key per reprice (retries dedup correctly).
REPRICE_IDEMPOTENCY_NAMESPACE = UUID("6b7c1f2a-0e4d-5a8b-9c3e-1d2f4a6b8c0d")


class MemberMembershipsReprice(MemberMembershipsTransitionBase):
    """Execute a reprice onto a target price (append-only, verify-or-revert)."""

    async def reprice(
        self,
        member_id: UUID,
        old_item_id: UUID,
        proration_behavior: ProrationBehavior,
        target_price_id: UUID | None = None,
    ) -> UUID:
        """Reprice one membership (DB-first); returns the successor item_id.

        target_price_id=None resolves the plan's active price; given pins a specific price.
        No-op if already on the target. DB phase is reverted on unconfirmed converge.
        """
        payer_id = await self._resolve_payer(old_item_id, member_id)
        async with self._paying_lock.lock([payer_id]):
            row = await self._get_membership(old_item_id, member_id)
            self._validate_reprice(row, old_item_id, member_id)

            if target_price_id is None:
                target_price = await self._get_active_price_for_plan(
                    row["gym_id"],
                    row["plan_id"],
                )
                target_price_id = UUID(str(target_price["price_id"]))
            else:
                target_price = await self._get_price_for_plan(
                    row["gym_id"],
                    row["plan_id"],
                    target_price_id,
                )

            if UUID(str(row["price_id"])) == target_price_id:
                return old_item_id  # Already on target — no-op.

            # Converge to a clean baseline before inserting the successor.
            await self._pre_sync_payments(payer_id)

            new_item_id = await self._write_db_phase(
                row,
                member_id,
                old_item_id,
                row["plan_id"],
                target_price_id,
                target_price,
            )

            # Stable key from immutable successor id — retries dedup at Stripe.
            reprice_idempotency_key = uuid5(
                REPRICE_IDEMPOTENCY_NAMESPACE,
                str(new_item_id),
            )

            await sync_or_revert(
                sync_fn=lambda: self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=reprice_idempotency_key,
                    proration_behavior=proration_behavior,
                ),
                revert_fn=lambda: self._revert_db_phase(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
                entity_name="member_membership_reprice",
                crm_pk=str(old_item_id),
                verify_fn=lambda: self._verify(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
            )
            return new_item_id

    def _validate_reprice(
        self,
        row: dict,
        old_item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate the membership can be repriced (recurring, no pending cancel/end)."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Can only reprice a recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot reprice a membership with a pending cancellation "
                f"— clear the cancellation first: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        if (
            row["end_date"] is not None
            and row["end_date"] <= gym_today(row["timezone"])
        ):
            raise ValueError(
                f"Cannot reprice ended membership: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
