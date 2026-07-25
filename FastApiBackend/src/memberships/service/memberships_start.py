"""Start memberships: validate → DB insert + discounts → one-time invoice + recurring converge.

At most two charges per request. Billed charges are never un-billed.

The response never claims less — or more — than what actually happened. A card
that did not collect is per-item DATA on the router's 207 (``card declined: …``)
— whether the bank refused it or the pay returned without collecting (SCA /
3-D Secure). Neither is an outage and both leave the desk with the same answer,
so a start has exactly TWO failure reasons: the card, or our side.

A system failure raises → 500 only *while nothing has been collected*; once the
one-time leg has charged it becomes per-item DATA too (``system failure: …`` →
207), because a 500 reading "nothing created" would lie about money that moved.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID, uuid5

import stripe
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
from src.payments.payments_exceptions import PaymentsNotCollectedError
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

# The reason prefix on a ``failed`` item's ``error``: the CARD failed, or OUR
# side broke. Staff act on each differently and clients switch on "starts with",
# so neither may be a prefix of the other or phrased as the other.
# Contract — test-locked in ``tests/memberships/test_start_207_contract.py``.
CARD_DECLINED_PREFIX = "card declined: "
SYSTEM_FAILURE_PREFIX = "system failure: "

# What a definitive NON-collection says. Stripe raises ``CardError`` with its
# own end-user wording on a refusal, but a pay that RETURNED without collecting
# carries only the SCA explanation retry-card uses, which is the wrong advice on
# a path that reports it as an ordinary card failure. Shared with charge-card so
# both spell it the same way.
CARD_NOT_CHARGED_REASON = "The card could not be charged."


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
        """Create memberships for the payer's family; returns per-membership breakdown."""
        payer, plan_prices = await self._validation.validate(request)

        states = [
            MemberMembershipsStartItemState(
                member_id=item.member_id,
                gym_id=request.gym_id,
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

        # Recurring billing requires the card be saved as default — reject early.
        payment = request.payment
        if payment is not None and recurring and not payment.set_default:
            raise ValueError(
                "a card on a request with a recurring membership must set "
                "set_default — recurring memberships always bill the saved "
                "default card",
            )

        # Promote card to default first — both charges bill the saved default.
        if payment is not None and payment.set_default:
            try:
                await self._set_default_card(
                    request.payer_member_id,
                    payment.payment_method_id,
                )
            except stripe.CardError as exc:
                # Runs BEFORE `_insert_all`, so there is nothing to clean up. A
                # decline is per-item data (router -> 207); a NON-card failure
                # is deliberately not caught here and stays a 500.
                return self._declined_before_charge(states, str(exc))

        # Pre-sync before inserting to establish a clean DB↔Stripe baseline.
        if recurring:
            await self._pre_sync_payments(request.payer_member_id)

        await self._insert_all(request, payer, plan_prices, states)

        # Whether THIS request's one-time leg already charged — decides how a
        # later recurring NON-card failure is reported (see that method).
        one_time_committed = False
        if one_time:
            try:
                one_time_committed = await self._charge_one_time_group(
                    request, one_time,
                )
            except Exception:
                # `_insert_all` committed the RECURRING rows too and their
                # converge will never run — provably un-billed, and an
                # uncancelled `not_added` row trips
                # `trg_recurring_no_active_memberships` on EVERY later retry (a
                # raw-DB 500 staff cannot even see). Sweep ONLY recurring: the
                # one-time group pays BEFORE its writeback, so it may be billed.
                await self._cleanup_states(recurring)
                raise
        if recurring:
            await self._converge_recurring_group(
                request,
                recurring,
                one_time_committed=one_time_committed,
            )

        charge_count = (1 if one_time else 0) + (1 if recurring else 0)
        return self._build_response(states, charge_count)

    # ── Response ───────────────────────────────────────────────

    def _build_response(
        self,
        states: list[MemberMembershipsStartItemState],
        charge_count: int,
    ) -> MemberMembershipsStartResponse:
        """Fold the working states into the per-membership start breakdown."""
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

    def _declined_before_charge(
        self,
        states: list[MemberMembershipsStartItemState],
        error: str,
    ) -> MemberMembershipsStartResponse:
        """Build an all-``failed`` breakdown for a decline BEFORE any insert.

        ``_set_default_card`` runs before ``_insert_all``, so no rows, discounts
        or charges exist and there is nothing to clean up: every item is
        ``failed`` with the decline reason and ``charge_count`` is 0 -> 207.
        """
        for state in states:
            state.status = MemberMembershipsStartStatus.failed
            state.error = f"{CARD_DECLINED_PREFIX}{error}"
        return self._build_response(states, charge_count=0)

    # ── Private — the phases ───────────────────────────────────

    async def _insert_all(
        self,
        request: MemberMembershipsStartRequest,
        payer: PayerProfile,
        plan_prices: dict[UUID, dict],
        states: list[MemberMembershipsStartItemState],
    ) -> None:
        """Insert pending rows + mint custom discounts + apply discounts (before any charge)."""
        start_date = gym_today(payer.timezone)
        rows = self._build_pending_rows(request, plan_prices, start_date)
        item_ids = await self._crm_insert(rows)
        for state, item_id in zip(states, item_ids, strict=True):
            state.item_id = item_id

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
                            allow_custom=True,  # Only start may apply custom discounts.
                        )
                    )
        except Exception:
            await self._cleanup_states(states)
            raise

    async def _charge_one_time_group(
        self,
        request: MemberMembershipsStartRequest,
        group: list[MemberMembershipsStartItemState],
    ) -> bool:
        """Charge one consolidated invoice for the one-time group.

        Returns whether the charge COMMITTED: ``True`` keeps the rows (billed
        lines are never un-billed, so a kept-but-unconfirmed row counts),
        ``False`` when the card did not collect, whose rows were cleaned. A
        system failure raises. The recurring arm needs this to know whether a
        later failure can still claim "nothing created".
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
                idempotency_key=uuid5(
                    request.idempotency_key, PlanType.one_time.value,
                ),
                paid_with_cash=request.paid_with_cash,
                payment_method_id=one_off_pm,
            )
        except stripe.CardError as exc:
            # A bank decline is a definitive result, not a server failure: fail
            # the group (its un-billed rows are cleaned) -> the router's 207.
            await self._fail_group(
                group, f"{CARD_DECLINED_PREFIX}{exc}", cleanup=True,
            )
            return False
        except PaymentsNotCollectedError:
            # The pay RETURNED without collecting (SCA / 3-D Secure). Nobody
            # refused, but nothing arrived either, so it is reported as the
            # ordinary card failure it is — same prefix, same 207. `cleanup=True`
            # is safe ONLY because the raise beat `PaymentSyncOneTime._writeback`:
            # the rows are still NULL `stripe_item_id` + `not_added`, provably
            # un-billed. MUST stay above the blanket arm — it subclasses it, and
            # a 500 here would report a card failure as an outage.
            await self._fail_group(
                group,
                f"{CARD_DECLINED_PREFIX}{CARD_NOT_CHARGED_REASON}",
                cleanup=True,
            )
            return False
        except Exception:
            # A SYSTEM failure — never dressed up as a card failure, which both
            # arms above answer. Clean THIS group and propagate to a
            # non-retryable 500. The request's RECURRING rows are swept by the
            # matching arm in ``start`` (this group may be billed).
            await self._cleanup_states(group)
            raise
        await self._verify_group(group, keep_unverified=True)
        # The invoice went through: even an unconfirmed writeback KEEPS its row
        # (billed lines are never un-billed), so money has moved from here on.
        return True

    async def _set_default_card(
        self,
        payer_member_id: UUID,
        payment_method_id: str,
    ) -> None:
        """Promote the card to the payer's saved default via update_card."""
        await self._members_management.update_card(
            payer_member_id,
            MembersBillingUpdateCardRequest(
                payment_method_id=payment_method_id,
            ),
        )

    async def _converge_recurring_group(
        self,
        request: MemberMembershipsStartRequest,
        group: list[MemberMembershipsStartItemState],
        *,
        one_time_committed: bool,
    ) -> None:
        """Converge the recurring group into Stripe; reverts unconfirmed rows.

        ``one_time_committed`` says whether the one-time leg of this SAME
        request already charged. It changes only how a NON-card failure here is
        reported — see that arm.
        """
        try:
            await self._payment_sync.update_payments_recurring(
                request.payer_member_id,
                idempotency_key=uuid5(
                    request.idempotency_key, PlanType.recurring.value,
                ),
                pay_first_invoice_out_of_band=request.paid_with_cash,
                proration_behavior=request.proration_behavior,
            )
        except stripe.CardError as exc:
            # A bank decline on the recurring first invoice
            # (`error_if_incomplete` 402s the create/update, leaving no
            # subscription). Definitive: fail + clean -> the router's 207.
            await self._fail_group(
                group, f"{CARD_DECLINED_PREFIX}{exc}", cleanup=True,
            )
            return
        except Exception as exc:
            # A NON-card failure, never dressed up as a decline. Either way the
            # group's un-billed rows go; what differs is how the request ANSWERS.
            await self._cleanup_states(group)
            if not one_time_committed:
                # Nothing in this request collected, so "nothing was created" is
                # literally true: propagate to a non-retryable 500.
                raise
            # The one-time leg already charged and `keep_unverified=True` KEPT
            # those billed rows, so a 500 saying "nothing created" would lie
            # about money that moved. Report per item instead -> the router's
            # 207 (a 2xx, so no proxy replays it). Swallowing the exception is
            # what would make the outage invisible, so log it with its stack.
            logger.error(
                "Start: the recurring converge failed AFTER the one-time leg "
                "already collected (payer_member_id=%s, gym_id=%s). The "
                "one-time memberships stand; the recurring items are reported "
                "failed with a system-failure reason on a 207.",
                request.payer_member_id,
                request.gym_id,
                exc_info=True,
            )
            await self._fail_group(
                group,
                # No form of "decline" appears here on purpose: staff read this
                # prose, and the card was never the problem.
                (
                    f"{SYSTEM_FAILURE_PREFIX}the recurring memberships could "
                    f"not be set up ({type(exc).__name__}). The card was not "
                    f"the problem — our side failed. The one-time purchase on "
                    f"this order WAS charged and is live; nothing recurring was "
                    f"created. Front desk must start the recurring items again."
                ),
                # Already cleaned above — do not delete twice.
                cleanup=False,
            )
            return
        await self._verify_group(group, keep_unverified=False)

    async def _verify_group(
        self,
        group: list[MemberMembershipsStartItemState],
        keep_unverified: bool,
    ) -> None:
        """Check each row flipped to applied.
        keep_unverified=True keeps billed-but-unconfirmed rows (never un-bill)."""
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
        """Delete un-billed rows: applied discounts → minted customs → pending rows (FK order)."""
        for state in states:
            if state.applied_ids:
                await self._update_discounts.delete_applied_discounts(
                    state.member_id, state.applied_ids,
                )
                state.applied_ids = []
            for discount_id in state.minted_ids:
                await self._discounts.delete_discount(discount_id, state.gym_id)
            state.minted_ids = []
        await self._delete_pending(
            [s.item_id for s in states if s.item_id is not None],
        )
