"""Start memberships: ONE list-based op, DB-first, at most two charges.

One request creates N memberships billed by ONE payer (a single
membership = a one-item list — there is no separate single-start path).
Per-membership discounts land BEFORE the charge, so the first (one-time:
only) invoice is discounted. Billing is at most two charges: ONE
consolidated one-time invoice (every non-recurring membership, one line
each) + ONE recurring converge. The op never links accounts — every
non-payer member must already be linked to the payer, which is what lets
the whole request run under the payer's single family lock.

Phases:
- A — validate everything up-front (``MemberMembershipsStartValidation``,
  shared with the preview); reject with nothing written or billed.
- B — pure DB: one multi-row pending insert + per-item minted customs +
  applied discounts; any failure undoes everything (nothing billed).
- C — the one one-time invoice charge.
- D — the one recurring converge.

Failure granularity is the charge group: a group's members share its fate,
a failed group never touches the other group's billed rows, and a
successful charge is NEVER un-billed.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID, uuid5

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.members.schema.members_billing_schema import (
    MembersBillingUpdateCardRequest,
)
from src.memberships.memberships_schema import (
    MemberMembershipsStartItemState,
    MemberMembershipsStartRequest,
    MemberMembershipsStartResponse,
    MemberMembershipsStartResultItem,
    MemberMembershipsStartStatus,
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
    from src.members.service.management.members_management_service import (
        MembersManagementService,
    )
    from src.memberships.service.memberships_discounts import (  # noqa: E501
        MemberMembershipsDiscounts,
    )
    from src.memberships.service.memberships_start_validation import (
        MemberMembershipsStartValidation,
    )
    from src.shared.payer_profile import PayerProfile
    from src.sync.service.sync_one_time import (
        PaymentSyncOneTime,
    )
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsStart(MemberMembershipsBase):
    """Create a family's memberships in one call (DB-first, two charges max)."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_sync_one_time: PaymentSyncOneTime,
        update_discounts: MemberMembershipsDiscounts,
        discounts_service: DiscountsService,
        validation: MemberMembershipsStartValidation,
        members_management_service: MembersManagementService,
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
        self._members_management = members_management_service

    async def start(
        self,
        request: MemberMembershipsStartRequest,
    ) -> MemberMembershipsStartResponse:
        """Create every membership in the request for the payer's family.

        Validates everything up-front (any validation failure rejects the
        whole request with nothing written or billed), inserts the pending
        rows + discounts, then bills: one consolidated invoice for the
        one-time group, one converge for the recurring group. Returns the
        per-membership breakdown — a failed charge group surfaces there,
        not as an exception.

        Raises:
            ValueError: If Phase A validation fails (nothing written).
        """
        payer, plan_prices = await self._validation.validate(request)

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
        one_time = [
            s for s in states if s.plan_type != PlanType.recurring
        ]
        recurring = [
            s for s in states if s.plan_type == PlanType.recurring
        ]

        # A card on a request that includes a recurring membership MUST be
        # saved as the default — recurring can only bill the payer's saved
        # default. Reject loudly before anything is written.
        payment = request.payment
        if payment is not None and recurring and not payment.set_default:
            raise ValueError(
                "a card on a request with a recurring membership must set "
                "set_default — recurring memberships always bill the saved "
                "default card",
            )

        # Pre-sync only when a recurring converge will run: converge the
        # payer's family to a clean DB↔Stripe baseline BEFORE inserting.
        if recurring:
            await self._pre_sync_payments(request.payer_member_id)

        await self._insert_all(request, payer, plan_prices, states)

        # Promote the card to the payer's saved default UP-FRONT (before any
        # charge) when asked, so it bills the one-time invoice AND the
        # recurring converge below. Recurring can only bill the saved default,
        # so the card has to be the default before the converge runs. If a
        # charge later fails the default already changed — that's accepted
        # (staff re-edit the card), never reverted.
        if payment is not None and payment.set_default:
            await self._set_default_card(
                request.payer_member_id,
                payment.payment_method_id,
            )

        if one_time:
            await self._charge_one_time_group(request, one_time)
        if recurring:
            await self._converge_recurring_group(request, recurring)

        charge_count = (1 if one_time else 0) + (1 if recurring else 0)
        return MemberMembershipsStartResponse(
            results=[
                MemberMembershipsStartResultItem(
                    member_id=s.member_id,
                    plan_id=s.plan_id,
                    plan_type=s.plan_type,
                    status=s.status,
                    item_id=(
                        s.item_id
                        if s.status == MemberMembershipsStartStatus.created
                        else None
                    ),
                    error=s.error,
                )
                for s in states
            ],
            charge_count=charge_count,
            multiple_charges=charge_count > 1,
        )

    # ── Private — the phases ───────────────────────────────────

    async def _insert_all(
        self,
        request: MemberMembershipsStartRequest,
        payer: PayerProfile,
        plan_prices: dict[UUID, dict],
        states: list[MemberMembershipsStartItemState],
    ) -> None:
        """Phase B (pure DB): pending rows + minted customs + discounts.

        All membership rows land in ONE multi-row insert; each item's inline
        customs are minted and its discounts applied before any charge. Any
        failure here undoes everything inserted so far and re-raises —
        nothing has been billed yet.
        """
        start_date = gym_today(payer.timezone)
        rows = self._build_pending_rows(request, plan_prices, start_date)
        inserted = await self._crm_insert(rows)
        for state in states:
            state.item_id = inserted[(state.member_id, state.plan_id)]

        try:
            for item, state in zip(
                request.memberships, states, strict=True,
            ):
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
                            # Minted by THIS start — the one flow allowed to
                            # apply a custom (single-use, DB-enforced).
                            allow_custom=True,
                        )
                    )
        except Exception:
            await self._cleanup_states(states)
            raise

    async def _charge_one_time_group(
        self,
        request: MemberMembershipsStartRequest,
        group: list[MemberMembershipsStartItemState],
    ) -> None:
        """Phase C: ONE consolidated invoice sweeps the pending one-time rows.

        The group shares the invoice's fate: an exception means nothing was
        billed (per-step Stripe idempotency) → the whole group fails and is
        cleaned up. After a successful charge an unconfirmed writeback marks
        the row failed but KEEPS it — its line is billed; never un-bill.

        A one-off card (``payment`` set, NOT ``set_default``) is charged
        directly (attach → pay → detach). When ``set_default`` the card was
        already promoted to the payer's default up-front in ``start()``, so the
        one-time invoice just bills the saved default like any other charge —
        no explicit payment method here.
        """
        payment = request.payment
        one_off_pm = (
            payment.payment_method_id
            if payment is not None and not payment.set_default
            else None
        )
        try:
            await self._payment_sync_one_time.charge_one_time(
                request.payer_member_id,
                # Each charge group's key derives from the request's single
                # key (named by its PlanType group), so a client retry of
                # the same request dedups BOTH charges at Stripe.
                idempotency_key=uuid5(
                    request.idempotency_key, PlanType.one_time.value,
                ),
                paid_with_cash=request.paid_with_cash,
                payment_method_id=one_off_pm,
            )
        except Exception as exc:
            await self._fail_group(
                group, f"one-time invoice failed: {exc}", cleanup=True,
            )
            return
        await self._verify_group(group, keep_unverified=True)

    async def _set_default_card(
        self,
        payer_member_id: UUID,
        payment_method_id: str,
    ) -> None:
        """Promote the one-off card to the payer's saved default — best effort.

        Reuses ``MembersManagementService.update_card`` (set customer default →
        detach the old default → write the members card cache). The card is
        already attached (the charge kept it), so the attach inside update_card
        is a no-op. A failure here must NOT un-bill the successful charge, so it
        is logged and swallowed — the card simply stays attached as a
        non-default method and staff can re-save it from the member page.
        """
        try:
            await self._members_management.update_card(
                payer_member_id,
                MembersBillingUpdateCardRequest(
                    payment_method_id=payment_method_id,
                ),
            )
        except Exception:
            logger.warning(
                "One-off card charged but promoting it to member %s's "
                "default failed; it stays attached (non-default).",
                payer_member_id,
                exc_info=True,
            )

    async def _converge_recurring_group(
        self,
        request: MemberMembershipsStartRequest,
        group: list[MemberMembershipsStartItemState],
    ) -> None:
        """Phase D: ONE recurring converge adds the pending recurring rows.

        An exception fails and cleans the whole group (the engine re-derives
        from the DB, so removing the pending rows is the revert). A row whose
        writeback is unconfirmed is reverted too — the next converge or the
        scheduled reconciler self-heals the Stripe side.
        """
        try:
            await self._payment_sync.update_payments_recurring(
                request.payer_member_id,
                idempotency_key=uuid5(
                    request.idempotency_key, PlanType.recurring.value,
                ),
                pay_first_invoice_out_of_band=request.paid_with_cash,
                proration_behavior=(
                    "always_invoice" if request.prorate else "none"
                ),
            )
        except Exception as exc:
            await self._fail_group(
                group, f"recurring sync failed: {exc}", cleanup=True,
            )
            return
        await self._verify_group(group, keep_unverified=False)

    async def _verify_group(
        self,
        group: list[MemberMembershipsStartItemState],
        keep_unverified: bool,
    ) -> None:
        """Verify each row's writeback flipped it to ``applied``.

        ``keep_unverified=True`` (one-time): the charge succeeded, so an
        unconfirmed row is marked failed but kept — its invoice line is
        already billed and is never un-billed. ``False`` (recurring): the
        row is reverted; the reconciler / next converge heals Stripe.
        """
        for state in group:
            status = await self._get_sync_status(
                state.item_id, state.member_id,
            )
            if status == StripeSyncStatus.applied:
                continue
            state.status = MemberMembershipsStartStatus.failed
            if keep_unverified:
                state.error = (
                    "charge succeeded but the sync writeback was not "
                    "confirmed — row kept (billed lines are never "
                    "un-billed); needs reconciliation"
                )
            else:
                state.error = "sync writeback not confirmed — row reverted"
                await self._cleanup_states([state])

    async def _fail_group(
        self,
        group: list[MemberMembershipsStartItemState],
        error: str,
        cleanup: bool,
    ) -> None:
        """Mark every state in the group failed; optionally clean its rows."""
        for state in group:
            state.status = MemberMembershipsStartStatus.failed
            state.error = error
        if cleanup:
            await self._cleanup_states(group)

    async def _cleanup_states(
        self,
        states: list[MemberMembershipsStartItemState],
    ) -> None:
        """Undo un-billed items: applied rows → minted customs → pending rows.

        FK order matters (applied discounts RESTRICT on the membership row).
        Only ever called for rows whose charge group did NOT bill.
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
