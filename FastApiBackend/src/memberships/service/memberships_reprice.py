"""The membership reprice operation (append-only, DB-first verify-or-revert).

A reprice never mutates the membership row — ``price_id`` and
``stripe_item_id`` are trigger-enforced immutable. ``reprice`` cancels the old
row effective today, inserts its successor at the target price **of the same
plan**, copies the live applied discounts onto the successor (ONE transaction),
then the EXISTING payment sync converges Stripe and the writeback stamps the
successor ``applied`` and the old row ``deleted``.

The cancel-old + insert-successor + copy-discounts + verify-or-revert machinery
lives on ``MemberMembershipsTransitionBase`` (shared with the cross-plan
``MemberMembershipsUpgrade`` op); this file holds only the reprice-specific
resolution (target a price of the *same* plan), the no-op short-circuit, and the
reprice validation.

A standalone membership operation that knows NOTHING about how it is dispatched
(the per-plan batch task today, a direct CRM call tomorrow): plain parameters
in, the successor's item_id out, and it handles its own failure with the
standard ``sync_or_revert`` contract — an unconfirmed converge REVERTS the DB
phase and raises, leaving the membership exactly as it was. This module imports
nothing from ``src.tasks``.
"""

from uuid import UUID, uuid4

from schema.task import ProrationBehavior

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_transition_base import (
    MemberMembershipsTransitionBase,
)
from src.shared.db_first_helpers import sync_or_revert
from src.shared.gym_timezone import gym_today


class MemberMembershipsReprice(MemberMembershipsTransitionBase):
    """Execute a reprice onto a target price (append-only, verify-or-revert)."""

    async def reprice(
        self,
        member_id: UUID,
        old_item_id: UUID,
        proration_behavior: ProrationBehavior,
        target_price_id: UUID | None = None,
    ) -> UUID:
        """Run one reprice (DB-first); returns the successor row's item_id.

        Takes the payer lock itself (the membership's ``paid_by_member_id``),
        converges synchronously, returns when done — a standalone op like
        ``cancel`` / ``start``. The single member-detail upgrade calls it
        directly (no task); the per-plan batch runs it per task item.

        ``target_price_id`` resolution:
        - **None** (the single, member-detail upgrade) → resolve the plan's
          current ``is_active`` price and reprice to it.
        - **given** (the batch pins the active price at batch-discovery time)
          → reprice to that exact price **as-is**, never re-checked against
          the plan's *current* active price. A newer price created before the
          item runs must NOT divert or fail the upgrade the user asked for (a
          deactivated CRM price keeps a usable Stripe price — `plans_price.py`
          never archives one).

        A membership already on the target is a no-op (returns its own
        item_id, no work, no bill).

        Raises:
            LockBusyError: The payer is busy.
            ValueError: The membership does not validate (not found,
                cancelled, ended), has no active price (None case), or the
                given target is not a price of its plan.
            SyncNotConfirmedError: The converge could not be confirmed on
                Stripe — the DB phase has been reverted, the membership is
                exactly as it was.
        """
        # ``paid_by_member_id`` is immutable, so resolving the payer before
        # locking is race-free — and the lock keys on the PAYER, not the
        # member: a child's membership paid by a parent must lock the parent's
        # subscription, the one this reprice converges.
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
                # Already on the target — a no-op (a duplicate request, or
                # already repriced). Nothing to do and nothing to bill: the
                # reconciler's sweep converges any DB↔Stripe drift, so there
                # is no defensive re-sync here.
                return old_item_id

            # Prorating op: converge the payer to a clean baseline first.
            await self._pre_sync_payments(payer_id)

            new_item_id = await self._write_db_phase(
                row,
                member_id,
                old_item_id,
                row["plan_id"],
                target_price_id,
                target_price,
            )

            await sync_or_revert(
                sync_fn=lambda: self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=uuid4(),
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
        """Validate the membership can be repriced."""
        # A set cancel_date (already effective OR a future, still-active
        # scheduled cancellation) blocks the reprice — the successor would have
        # no cancel_date, silently dropping the pending cancellation. Staff
        # clear the cancellation first.
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
