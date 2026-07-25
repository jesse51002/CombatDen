"""Start memberships: validate → DB insert + discounts → one-time invoice + recurring converge.

At most two charges per request. Billed charges are never un-billed.

Failure reporting follows one rule: **the response never claims less than what
actually happened.** A bank decline is per-item DATA (``card declined: …`` → the
router's 207). A system failure raises → 500 *while nothing has been collected*;
once the one-time leg of the same request has charged, the same system failure
becomes per-item DATA too (``system failure: …`` → 207), because a 500 whose
contract reads "nothing created" would be a lie about money that moved.
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

# The two reason prefixes stamped on a ``failed`` result item's ``error``. They
# are the greppable, stable discriminator between the only two ways a start can
# fail once it has begun: the BANK said no, or OUR side broke. Staff act on them
# differently (another card vs. finish it at the desk) and monitoring must not
# confuse an ordinary decline with an outage, so neither is ever phrased as the
# other. Part of the API contract — see
# ``MemberMembershipsStartResultItem``; the prose after the prefix is free to
# change, the prefix is not.
CARD_DECLINED_PREFIX = "card declined: "
SYSTEM_FAILURE_PREFIX = "system failure: "


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
                # A GENUINE bank decline while saving the entered card as the
                # payer's default. This runs BEFORE `_insert_all`, so no rows,
                # discounts or charges exist yet — nothing was billed and there
                # is nothing to clean up. Surface it as the per-item `failed`
                # breakdown the client already consumes (the router maps any
                # failed item -> 207), NOT a 500. A NON-card Stripe / system
                # failure is deliberately NOT caught here — it stays a
                # non-retryable 500, because a system failure is not a decline.
                return self._declined_before_charge(states, str(exc))

        # Pre-sync before inserting to establish a clean DB↔Stripe baseline.
        if recurring:
            await self._pre_sync_payments(request.payer_member_id)

        await self._insert_all(request, payer, plan_prices, states)

        # Whether the one-time leg of THIS request already committed a charge.
        # It decides how a later NON-card failure in the recurring converge is
        # reported: once money has moved and live rows are kept, the request can
        # no longer honestly answer the router's 500 ("nothing created") — see
        # ``_converge_recurring_group``.
        one_time_committed = False
        if one_time:
            try:
                one_time_committed = await self._charge_one_time_group(
                    request, one_time,
                )
            except Exception:
                # A NON-card failure on the one-time leg (a decline never
                # reaches here — it is data, folded in by that arm). It cleaned
                # up its OWN group and re-raised, but `_insert_all` committed
                # EVERY row of the request in one insert, so the recurring rows
                # are sitting there `not_added` — and their converge below is
                # now never going to run, which is precisely what makes them
                # provably UN-BILLED: no `stripe_item_id`, no subscription item,
                # and the payer lock this op holds keeps the reconciler's push
                # sweep from converging them behind our back. So they are safe
                # to delete, and leaving them STRANDS the member behind a
                # permanent failure over a charge that never happened:
                #  - EVERY retry dies in `_insert_all`, whatever key it carries.
                #    `trg_recurring_no_active_memberships` is a BEFORE INSERT
                #    trigger that counts an uncancelled `not_added` row as
                #    active (it skips only `preview_add`), so the ghost rejects
                #    the replacement row with a raw DB error -> the router's
                #    500. It fires BEFORE the INSERT's
                #    `ON CONFLICT (idempotency_key) DO NOTHING` is resolved, so
                #    a same-key retry never even reaches the RETURNING-shortfall
                #    check that would have called it a 409 replay.
                #  - and nothing can explain that to staff, because the row is
                #    invisible: validation reads `member_memberships_status`,
                #    which HIDES `not_added`, so the request clears every check
                #    and then 500s on a membership nobody can see.
                # So the member cannot buy that recurring plan until the
                # reconciler's orphan sweep happens to run. `_crm_insert` says
                # this must never happen ("rather than committing a ghost
                # `not_added` row that is never charged or cleaned up"); this is
                # the arm that was breaking that promise.
                #
                # ONLY the recurring group is swept. The one-time group is
                # deliberately left to its own arm, because it may ALREADY BE
                # BILLED — `charge_one_time` pays the invoice and THEN does its
                # writeback, so a post-payment failure lands in that same arm —
                # and a billed line is never un-billed here.
                #
                # The raise still reaches the router as a 500, unchanged: the
                # recurring side collected nothing and now holds no rows, so
                # "nothing created and nothing charged" stays literally true for
                # it.
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

        The card was declined while being promoted to the payer's default
        (``_set_default_card``), which runs before ``_insert_all`` — so no rows,
        discounts or charges exist and there is nothing to clean up. Every
        requested membership is marked ``failed`` with the decline reason and
        ``charge_count`` is 0 (nothing was ever charged). The router maps the
        failed items to a 207, the decline contract the client already consumes.
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
        Keeps rows on success — billed lines are never un-billed.

        Returns:
            Whether the charge COMMITTED — i.e. the invoice went through and its
            rows are kept (``_verify_group(keep_unverified=True)`` never un-bills
            a billed line, so a kept-but-unconfirmed row still counts). ``False``
            only on a decline, where the group's rows were cleaned up and
            nothing was collected. A non-card failure raises instead, so it never
            returns. The recurring arm needs this answer to know whether a later
            failure can still claim "nothing created".
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
            # A GENUINE bank decline on the one-time invoice — a definitive
            # result, not a server failure. Fail the group (its un-billed
            # pending rows are cleaned up) so the response carries a `failed`
            # item -> the router's 207 decline contract, never a 500.
            await self._fail_group(
                group, f"{CARD_DECLINED_PREFIX}{exc}", cleanup=True,
            )
            return False
        except Exception:
            # Any NON-card failure (a Stripe system/gateway error, a network
            # timeout, a rate limit) is NOT a decline. Clean up THIS group's
            # pending rows and propagate so the router returns a non-retryable
            # 500 — a system failure must never masquerade as "your card was
            # declined". The same request's RECURRING rows are swept by the
            # matching arm in ``start`` (they are provably un-billed, which this
            # group may not be), so no ghost row outlives the raise.
            await self._cleanup_states(group)
            raise
        await self._verify_group(group, keep_unverified=True)
        # The invoice went through. Even a row whose writeback could not be
        # confirmed is KEPT and flagged (billed lines are never un-billed), so
        # from here on this request has moved money whatever else fails.
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
            # A GENUINE bank decline on the recurring first invoice (the card
            # path's `error_if_incomplete` 402s the create/update and leaves no
            # subscription / rolls the item change back). A definitive result,
            # not a server failure: fail the group (its un-billed pending rows
            # are cleaned up) so the response carries a `failed` item -> the
            # router's 207 decline contract, never a 500.
            await self._fail_group(
                group, f"{CARD_DECLINED_PREFIX}{exc}", cleanup=True,
            )
            return
        except Exception as exc:
            # Any NON-card failure (a Stripe system/gateway error, a lost
            # subscription, a network timeout) is NOT a decline, and is never
            # dressed up as one. Either way the recurring group's un-billed
            # pending rows go (nothing half-committed); what differs is how the
            # request ANSWERS.
            await self._cleanup_states(group)
            if not one_time_committed:
                # Nothing in this request ever collected, so "the whole start
                # failed and nothing was created" is the literal truth:
                # propagate and let the router answer a non-retryable 500.
                raise
            # The one-time leg of this SAME request already charged, and
            # `_verify_group(keep_unverified=True)` deliberately KEEPS those
            # billed rows — so a live membership exists and money has moved. The
            # 500's contract says "nothing created", which would now be a flat
            # lie about a collected charge; the house rule is that a 2xx no
            # longer implies money moved and the client branches on the per-item
            # result. So report the truth per item instead: these recurring
            # items `failed` -> the router's 207, carrying a SYSTEM-FAILURE
            # reason that is unmistakably not a bank decline (another card
            # cannot fix this; staff must finish it). 207 is a 2xx, so no proxy
            # auto-replays this money-moving request either.
            #
            # Swallowing the exception is what would otherwise make the outage
            # invisible — the router never sees it — so it is logged HERE, with
            # the stack, before the group is folded into the response.
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
                # No form of the word "decline" appears here on purpose: this
                # reason is read by staff (and matched by clients) and the card
                # was never the problem — saying so in passing invites exactly
                # the misread the prefix exists to prevent.
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
