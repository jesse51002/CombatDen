"""The start op's preview: a staged, DISCOUNTED dry-run, three-way split.

Runs the IDENTICAL Phase A validation as the real start (the shared
``MemberMembershipsStartValidation``), stages every item exactly as the real
start would — pending rows as ``preview_add`` plus their applied-discount
rows (inline customs minted, then archived again in cleanup) — runs the two
engine previews against that staged state, and ALWAYS undoes the staging in
a ``finally``. The real path excludes ``preview_add`` rows, so the staging
can never bill; the per-family lock (held by the facade) keeps a concurrent
real sync from observing it.

The response is the three-way split: ``one_time`` (the consolidated
one-time invoice), ``due_now`` (the recurring proration charged now),
``recurring`` (the steady-state per-cycle invoice).
"""

from __future__ import annotations

import logging
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.memberships.memberships_schema import (
    MemberMembershipsStartItemState,
    MemberMembershipsStartPreviewResponse,
    MemberMembershipsStartRequest,
)
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today

if TYPE_CHECKING:
    from src.discounts.service.discounts_service import (
        DiscountsService,
    )
    from src.memberships.service.memberships_discounts import (  # noqa: E501
        MemberMembershipsDiscounts,
    )
    from src.memberships.service.memberships_start_validation import (
        MemberMembershipsStartValidation,
    )
    from src.sync.service.sync_one_time import (
        PaymentSyncOneTime,
    )
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsStartPreview(MemberMembershipsBase):
    """Staged, discounted dry-run of the start op (no charge, no residue)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_sync_one_time: PaymentSyncOneTime,
        update_discounts: MemberMembershipsDiscounts,
        discounts_service: DiscountsService,
        validation: MemberMembershipsStartValidation,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_sync_one_time = payment_sync_one_time
        self._update_discounts = update_discounts
        self._discounts = discounts_service
        self._validation = validation

    async def preview(
        self,
        request: MemberMembershipsStartRequest,
    ) -> MemberMembershipsStartPreviewResponse:
        """Preview what starting the request's memberships would charge.

        Runs every validation the real start runs, stages the rows +
        discounts as ``preview_add``, reads the two engine previews, and
        cleans the staging up — nothing is charged and nothing persists.

        Raises:
            ValueError: If Phase A validation fails.
        """
        parent, plan_prices = await self._validation.validate(request)

        states = [
            MemberMembershipsStartItemState(
                member_id=item.member_id,
                plan_id=plan_prices[item.price_id]["plan_id"],
                plan_type=PlanType(
                    plan_prices[item.price_id]["plan_type"],
                ),
            )
            for item in request.memberships
        ]
        has_one_time = any(
            s.plan_type != PlanType.recurring for s in states
        )
        has_recurring = any(
            s.plan_type == PlanType.recurring for s in states
        )

        start_date = gym_today(parent.timezone)
        try:
            await self._stage(request, plan_prices, states, start_date)

            one_time = (
                await self._payment_sync_one_time.preview_one_time(
                    request.payer_member_id,
                )
                if has_one_time
                else None
            )
            split = (
                await self._payment_sync.preview_update_payments_recurring(
                    request.payer_member_id,
                    proration_behavior=(
                        "always_invoice" if request.prorate else "none"
                    ),
                )
                if has_recurring
                else None
            )
        finally:
            await self._cleanup(states)

        return MemberMembershipsStartPreviewResponse(
            one_time=one_time,
            due_now=split.due_now if split else None,
            recurring=split.recurring if split else None,
        )

    # ── Private — stage / cleanup ──────────────────────────────

    async def _stage(
        self,
        request: MemberMembershipsStartRequest,
        plan_prices: dict[UUID, dict],
        states: list[MemberMembershipsStartItemState],
        start_date: date,
    ) -> None:
        """Stage the request exactly as the real start would, as preview rows.

        The same multi-row insert (``preview_add``) and the same per-item
        discount staging (inline customs minted + applied) — so the engine
        previews read precisely the state the real start would bill.
        """
        rows = self._build_pending_rows(
            request,
            plan_prices,
            start_date,
            sync_status=StripeSyncStatus.preview_add,
        )
        inserted = await self._crm_insert(rows)
        for state in states:
            state.item_id = inserted[(state.member_id, state.plan_id)]

        for item, state in zip(request.memberships, states, strict=True):
            state.minted_ids = await self._discounts.mint_custom_discounts(
                request.gym_id, item.custom_discounts,
            )
            all_discount_ids = [*item.discount_ids, *state.minted_ids]
            if all_discount_ids:
                state.applied_ids = (
                    await self._update_discounts.add_applied_discounts(
                        item_id=state.item_id,
                        member_id=item.member_id,
                        gym_id=request.gym_id,
                        discount_ids=all_discount_ids,
                        apply_date=start_date,
                        sync_status=StripeSyncStatus.preview_add,
                        # Minted by THIS preview; the staging is always
                        # undone, so the custom is archived un-applied.
                        allow_custom=True,
                    )
                )

    async def _cleanup(
        self,
        states: list[MemberMembershipsStartItemState],
    ) -> None:
        """Undo the staging: applied rows → minted customs → pending rows.

        FK order matters (applied discounts RESTRICT on the membership
        row). Runs in the preview's ``finally`` — a preview never commits
        anything.
        """
        for state in states:
            if state.applied_ids:
                await self._update_discounts.delete_applied_discounts(
                    state.member_id, state.applied_ids,
                )
                state.applied_ids = []
            for discount_id in state.minted_ids:
                await self._discounts.delete_discount(discount_id)
            state.minted_ids = []
        await self._delete_pending(
            [s.item_id for s in states if s.item_id is not None],
        )
