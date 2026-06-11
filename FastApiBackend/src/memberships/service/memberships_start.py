"""Start (create) a new membership: DB first, then Stripe, then set stripe ID."""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID, uuid5

from schema.gym_discount import DiscountType
from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import (
    DiscountValue,
)
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsBatchStartRequest,
    MemberMembershipsBatchStartResponse,
    MemberMembershipsBatchStartResultItem,
    MemberMembershipsBatchStartStatus,
)
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
    PreviewInvoice,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentPreviewRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import (
    staged_preview,
    sync_or_revert,
)
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.discounts.service.discounts_service import (
        DiscountsService,
    )
    from src.memberships.service.memberships_discounts import (  # noqa: E501
        MemberMembershipsDiscounts,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.billing_parent import ParentProfile
    from src.shared.billing_parent_resolver import BillingParentResolver
    from src.sync.service.sync_one_time import (
        PaymentSyncOneTime,
    )
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)

# The two charge groups derive their Stripe idempotency keys from the
# request's single key, so a client retry of the same request dedups BOTH
# charges at Stripe.
ONE_TIME_KEY_NAME = "one_time"
RECURRING_KEY_NAME = "recurring"


@dataclass
class _StartItemState:
    """Per-item working state across the start phases (internal only)."""

    member_id: UUID
    plan_id: UUID
    plan_type: PlanType
    item_id: UUID | None = None
    applied_ids: list[UUID] = field(default_factory=list)
    minted_ids: list[UUID] = field(default_factory=list)
    status: MemberMembershipsBatchStartStatus = (
        MemberMembershipsBatchStartStatus.created
    )
    error: str | None = None


class MemberMembershipsStart(MemberMembershipsBase):
    """Create a new membership using the DB-first pattern."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
        parent_resolver: BillingParentResolver,
        payment_sync_one_time: PaymentSyncOneTime,
        update_discounts: MemberMembershipsDiscounts,
        discounts_service: DiscountsService,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service
        self._parent_resolver = parent_resolver
        self._payment_sync_one_time = payment_sync_one_time
        self._update_discounts = update_discounts
        self._discounts = discounts_service

    async def start(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        idempotency_key: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
        discount_ids: list[UUID] | None = None,
        custom_discounts: list[DiscountValue] | None = None,
    ) -> None:
        """Start a new membership for a member.

        Validates the plan/price, checks no duplicate active
        membership exists, ensures the account is not frozen,
        inserts the CRM row, syncs to Stripe, then sets the
        stripe_item_id on the CRM row. Memberships always begin
        on the day this method is called — future start dates
        are not supported. Optional ``discount_ids`` / ``custom_discounts`` are
        applied before the first charge, so it is discounted at creation.

        Args:
            member_id: The member.
            gym_id: The gym.
            plan_id: The membership plan.
            price_id: The price tier.
            prorate: Whether to prorate the first charge.
            paid_with_cash: If True, the first invoice is marked
                paid out of band in Stripe instead of charging the
                customer's default payment method. Cash is a
                backup — future billing cycles still auto-charge
                the card as normal.

        Raises:
            ValueError: If plan/price invalid, membership already
                exists, or account is frozen.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        plan_prices = await self._get_plan_prices(gym_id, [(plan_id, price_id)])
        plan_price = plan_prices[(plan_id, price_id)]
        await self._check_no_existing(member_id, gym_id, [plan_id])

        parent = await self._parent_resolver.resolve_parent(member_id)
        if parent.is_frozen:
            raise ValueError("Cannot start membership: account is frozen")

        start_date = gym_today(parent.timezone)
        plan_type = PlanType(plan_price["plan_type"])
        is_recurring = plan_type == PlanType.recurring

        # ── Calculate dates ────────────────────────────────────
        end_date: date | None = None
        if not is_recurring and plan_price["duration_amount"] and plan_price["duration_unit"]:
            end_date = self._calculate_end_date(
                start_date,
                plan_price["duration_amount"],
                plan_price["duration_unit"],
            )

        if not plan_price["stripe_price_id"]:
            raise ValueError(f"Plan price {plan_price['price_id']} missing stripe_price_id")

        # Pre-sync (recurring): converge the family to a clean DB↔Stripe baseline
        # before inserting the new membership. (One-time has no subscription to
        # converge.)
        if is_recurring:
            await self._pre_sync_payments(member_id)

        # ── Step 1: DB insert (NULL stripe_item_id) ───────────
        inserted = await self._crm_insert([
            {
                "member_id": member_id,
                "gym_id": gym_id,
                "plan_id": plan_id,
                "price_id": price_id,
                "start_date": start_date,
                "end_date": end_date,
                "last_paid_date": start_date,
                "next_due_date": None,
                "stripe_item_id": None,
                "prorate": prorate,
                "total_price": plan_price["price"],
            },
        ])
        item_id = inserted[(member_id, plan_id)]

        # ── Discounts at creation (both paths) ────────────────
        # Mint any inline customs, then apply all presets (preset + minted)
        # BEFORE the engine call, so the first (one-time: only) invoice is
        # discounted. The revert undoes applied rows + minted customs + the pending
        # row together if the charge/sync then fails.
        minted_ids = await self._discounts.mint_custom_discounts(
            gym_id, custom_discounts or []
        )
        all_discount_ids = [*(discount_ids or []), *minted_ids]
        applied_ids: list[UUID] = []
        if all_discount_ids:
            applied_ids = await self._update_discounts.add_applied_discounts(
                item_id=item_id,
                member_id=member_id,
                gym_id=gym_id,
                discount_ids=all_discount_ids,
                apply_date=start_date,
                # The customs in this list were minted by THIS start — the one
                # flow allowed to apply a custom (single-use, DB-enforced).
                allow_custom=True,
            )

        async def _revert() -> None:
            if applied_ids:
                await self._update_discounts.delete_applied_discounts(
                    member_id, applied_ids
                )
            for discount_id in minted_ids:
                await self._discounts.delete_discount(discount_id)
            await self._delete_pending([item_id])

        # ── Step 2: charge / sync ─────────────────────────────
        # Both paths are DB-first + verified: the pending row inserted above is
        # visible to the engine, which pushes it to Stripe and writes its ids /
        # 'applied' status back itself (recurring → the subscription sync;
        # one-time → the consolidated invoice charge). Nothing to stamp here.
        if is_recurring:
            # Recurring is DB-first + verified: the sync adds the pending row to
            # Stripe and writes its line id / next_due_date / 'applied' status
            # back. If the sync fails or the row is not stamped 'applied', the
            # pending row is deleted so the DB stays in sync with Stripe.
            async def _sync_recurring() -> None:
                await self._payment_sync.update_payments_recurring(
                    member_id,
                    idempotency_key=idempotency_key,
                    pay_first_invoice_out_of_band=paid_with_cash,
                    proration_behavior=(
                        "always_invoice" if prorate else "none"
                    ),
                )

            async def _verify_added() -> bool:
                status = await self._get_sync_status(item_id, member_id)
                return status == StripeSyncStatus.applied

            await sync_or_revert(
                sync_fn=_sync_recurring,
                revert_fn=_revert,
                entity_name="member_membership",
                crm_pk=str(item_id),
                verify_fn=_verify_added,
            )
        else:
            # One-time is DB-first + verified, like recurring: the pending row is
            # visible to the one-time charge, which cuts a single invoice and
            # writes its line id + stripe_one_time_invoice_id + total_price +
            # 'applied' back itself. If the charge fails or the row is not stamped
            # 'applied', the pending row is deleted so the DB stays in sync.
            async def _run_charge() -> None:
                await self._payment_sync_one_time.charge_one_time(
                    member_id,
                    idempotency_key=idempotency_key,
                    paid_with_cash=paid_with_cash,
                )

            async def _verify_charged() -> bool:
                status = await self._get_sync_status(item_id, member_id)
                return status == StripeSyncStatus.applied

            await sync_or_revert(
                sync_fn=_run_charge,
                revert_fn=_revert,
                entity_name="member_membership",
                crm_pk=str(item_id),
                verify_fn=_verify_charged,
            )

    async def preview(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what starting a membership would charge.

        Runs every validation ``start`` runs (plan/price lookup,
        duplicate check, frozen-account check) and then calls the
        corresponding Stripe invoice preview instead of creating
        rows or subscriptions.

        Args:
            Identical to ``start``. ``paid_with_cash`` is accepted
            for signature parity but has no effect — preview
            performs no charge.

        Returns:
            A due-now / recurring split, or ``None`` for a recurring
            plan whose resulting bucket produces no upcoming invoice.
            A one-time plan returns the whole charge in ``due_now``
            with an empty ``recurring``.

        Raises:
            ValueError: Same conditions as ``start``.
        """
        plan_prices = await self._get_plan_prices(gym_id, [(plan_id, price_id)])
        plan_price = plan_prices[(plan_id, price_id)]
        await self._check_no_existing(member_id, gym_id, [plan_id])

        parent = await self._parent_resolver.resolve_parent(member_id)
        if parent.is_frozen:
            raise ValueError("Cannot start membership: account is frozen")

        if not plan_price["stripe_price_id"]:
            raise ValueError(f"Plan price {plan_price['price_id']} missing stripe_price_id")

        plan_type = PlanType(plan_price["plan_type"])
        is_recurring = plan_type == PlanType.recurring

        if is_recurring:
            # Stage a 'preview_add' membership row so the preview reflects the new
            # membership, then delete it (finally). The real path excludes
            # preview_add (can never bill it); the preview build (preview=True)
            # includes it. Race vs a concurrent real sync is bounded by the
            # cleanup; the per-parent lock (#25) closes it (TODO).
            start_date = gym_today(parent.timezone)
            staged: list[UUID] = []

            async def _stage() -> None:
                inserted = await self._crm_insert([
                    {
                        "member_id": member_id,
                        "gym_id": gym_id,
                        "plan_id": plan_id,
                        "price_id": price_id,
                        "start_date": start_date,
                        "end_date": None,
                        "last_paid_date": start_date,
                        "next_due_date": None,
                        "stripe_item_id": None,
                        "prorate": prorate,
                        "total_price": plan_price["price"],
                        "sync_status": StripeSyncStatus.preview_add,
                    },
                ])
                staged.append(inserted[(member_id, plan_id)])

            async def _cleanup() -> None:
                await self._delete_pending(staged)

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=_cleanup,
                preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                    member_id,
                    proration_behavior=(
                        "always_invoice" if prorate else "none"
                    ),
                ),
            )

        # A one-time purchase is charged entirely now; nothing recurs.
        one_time = await self._preview_one_time(
            stripe_customer_id=parent.stripe_customer_id,
            stripe_price_id=plan_price["stripe_price_id"],
            gym_id=parent.gym_id,
        )
        return DueNowVsRecurringPreview(due_now=one_time, recurring=None)

    # ── Private ────────────────────────────────────────────────
    #
    # The row-level helpers (_get_plan_price / _check_no_existing /
    # _crm_insert / _delete_pending / _calculate_end_date) live on
    # MemberMembershipsBase.

    # ── List-start Phase A — validate everything up-front ──────
    #
    # The start op is becoming ONE list-based implementation (a single
    # membership = a one-item list): one request creates N memberships for a
    # paying parent's family, discounts at creation, billed in at most two
    # charges (ONE consolidated one-time invoice + ONE recurring converge).
    # The list start never links accounts — every non-payer member must
    # already be linked to the payer, which is what lets the whole op run
    # under the payer's single family lock.
    #
    # Phase A rejects with nothing written or billed. Order: payer →
    # link/gym state → per-item plan/price + duplicate → discounts. The
    # request validator already rejected an empty list and intra-request
    # (member_id, plan_id) duplicates. These methods are unreachable until
    # the public ``start`` swaps to the list signature (Phases B–D land
    # first as private machinery).

    async def _validate_request(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> tuple[ParentProfile, dict[tuple[UUID, UUID], dict]]:
        """Run every up-front check; return the payer + plan/price rows.

        Returns:
            The resolved payer profile and the validated plan/price row per
            ``(plan_id, price_id)`` pair — downstream phases reuse them
            (timezone, price, plan_type, duration) without re-reading.

        Raises:
            ValueError: On the first failed check.
        """
        parent = await self._resolve_payer(request)
        await self._check_links(request)

        pairs = list({
            (item.plan_id, item.price_id) for item in request.memberships
        })
        plan_prices = await self._get_plan_prices(request.gym_id, pairs)
        for plan_id, price_id in pairs:
            if not plan_prices[(plan_id, price_id)]["stripe_price_id"]:
                raise ValueError(
                    f"Plan price {price_id} missing stripe_price_id",
                )

        plans_by_member: dict[UUID, list[UUID]] = {}
        for item in request.memberships:
            plans_by_member.setdefault(item.member_id, []).append(
                item.plan_id,
            )
        for member_id, plan_ids in plans_by_member.items():
            await self._check_no_existing(
                member_id, request.gym_id, plan_ids,
            )

        await self._check_discounts(request)
        return parent, plan_prices

    async def _resolve_payer(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> ParentProfile:
        """Validate the payer is a top-level, in-gym, unfrozen paying account.

        ``resolve_parent`` already raises if the resolved account has no
        Stripe customer; card presence is not pre-checked (a missing card
        surfaces as the charge's own failure, and ``paid_with_cash`` needs
        no card).

        Raises:
            ValueError: If the payer is itself linked to another paying
                account, is in a different gym, or is frozen.
        """
        parent = await self._parent_resolver.resolve_parent(
            request.payer_member_id,
        )
        if parent.member_id != request.payer_member_id:
            raise ValueError(
                f"Payer {request.payer_member_id} is linked to paying account "
                f"{parent.member_id} — the payer must be a top-level "
                f"paying account",
            )
        if parent.gym_id != request.gym_id:
            raise ValueError(
                f"Payer {request.payer_member_id} is not in gym {request.gym_id}",
            )
        if parent.is_frozen:
            raise ValueError(
                "Cannot start memberships: payer account is frozen",
            )
        return parent

    async def _check_links(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> None:
        """Every member exists, is in the gym, and is linked to THIS payer.

        The start op never links — an unlinked or differently-linked member
        is rejected with a "link them first" error. The payer itself (when
        it appears in the items) was already validated as top-level by
        ``_resolve_payer``.

        Raises:
            ValueError: If a member is missing, in another gym, unlinked,
                or linked to a different payer.
        """
        member_ids = {
            item.member_id
            for item in request.memberships
            if item.member_id != request.payer_member_id
        }
        if not member_ids:
            return

        sql = load_sql(SQL_DIR / "member_memberships_start_account_links.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in member_ids]},
            )
            rows = {UUID(str(r["member_id"])): r for r in result.mappings()}

        for member_id in member_ids:
            row = rows.get(member_id)
            if row is None:
                raise ValueError(f"Member {member_id} not found")
            if UUID(str(row["gym_id"])) != request.gym_id:
                raise ValueError(
                    f"Member {member_id} is not in gym {request.gym_id}",
                )
            linked_to = row["account_linked_to_id"]
            if linked_to is None:
                raise ValueError(
                    f"Member {member_id} is not linked to payer "
                    f"{request.payer_member_id} — link them first, then start "
                    f"(the start op never links accounts)",
                )
            if UUID(str(linked_to)) != request.payer_member_id:
                raise ValueError(
                    f"Member {member_id} is linked to a different paying "
                    f"account ({linked_to}) — unlink them first or use that "
                    f"account as the payer",
                )

    async def _check_discounts(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> None:
        """Every requested discount_id is live, in-gym, and not ``custom``.

        One read over the request's distinct ids. Customs are creation-only
        inline values (``custom_discounts``) — referencing an existing
        ``custom`` discount by id is always rejected. The inline
        ``custom_discounts`` need no check here: ``DiscountValue``
        self-validates.

        Raises:
            ValueError: If a discount is missing/archived/cross-gym or is a
                ``custom`` discount.
        """
        discount_ids = {
            discount_id
            for item in request.memberships
            for discount_id in item.discount_ids
        }
        if not discount_ids:
            return

        sql = load_sql(SQL_DIR / "member_memberships_start_discounts_check.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "discount_ids": [str(uid) for uid in discount_ids],
                    "gym_id": str(request.gym_id),
                },
            )
            rows = {UUID(str(r["discount_id"])): r for r in result.mappings()}

        for discount_id in discount_ids:
            row = rows.get(discount_id)
            if row is None:
                raise ValueError(
                    f"Discount {discount_id} not found in gym "
                    f"{request.gym_id} (or it is archived / has no active "
                    f"value version)",
                )
            if row["discount_type"] == DiscountType.custom.value:
                raise ValueError(
                    f"Discount {discount_id} is a custom discount — customs "
                    f"are single-use inline values (custom_discounts), never "
                    f"referenced by id",
                )

    # ── List-start Phases B–D (private machinery) ──────────────
    #
    # Unreachable until the public ``start`` swaps to the list signature.
    # B = pure DB (one multi-row insert + per-item discounts; any failure
    # undoes everything — nothing billed). C = the one one-time invoice
    # charge. D = the one recurring converge. Failure granularity is the
    # charge group (locked): a group's members share its fate, a failed
    # group never touches the other group's billed rows, and a successful
    # charge is NEVER un-billed.

    async def _start_all(
        self,
        request: MemberMembershipsBatchStartRequest,
    ) -> MemberMembershipsBatchStartResponse:
        """Run the start end-to-end: validate, insert, charge, converge.

        Raises:
            ValueError: If Phase A validation fails (nothing written).
        """
        parent, plan_prices = await self._validate_request(request)

        states = [
            _StartItemState(
                member_id=item.member_id,
                plan_id=item.plan_id,
                plan_type=PlanType(
                    plan_prices[(item.plan_id, item.price_id)]["plan_type"],
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

        # Pre-sync only when a recurring converge will run: converge the
        # payer's family to a clean DB↔Stripe baseline BEFORE inserting.
        if recurring:
            await self._pre_sync_payments(request.payer_member_id)

        await self._insert_all(request, parent, plan_prices, states)

        if one_time:
            await self._charge_one_time_group(request, one_time)
        if recurring:
            await self._converge_recurring_group(request, recurring)

        charge_count = (1 if one_time else 0) + (1 if recurring else 0)
        return MemberMembershipsBatchStartResponse(
            results=[
                MemberMembershipsBatchStartResultItem(
                    member_id=s.member_id,
                    plan_id=s.plan_id,
                    plan_type=s.plan_type,
                    status=s.status,
                    item_id=(
                        s.item_id
                        if s.status
                        == MemberMembershipsBatchStartStatus.created
                        else None
                    ),
                    error=s.error,
                )
                for s in states
            ],
            charge_count=charge_count,
            multiple_charges=charge_count > 1,
        )

    async def _insert_all(
        self,
        request: MemberMembershipsBatchStartRequest,
        parent: ParentProfile,
        plan_prices: dict[tuple[UUID, UUID], dict],
        states: list[_StartItemState],
    ) -> None:
        """Phase B (pure DB): pending rows + minted customs + discounts.

        All membership rows land in ONE multi-row insert; each item's inline
        customs are minted and its discounts applied before any charge. Any
        failure here undoes everything inserted so far and re-raises —
        nothing has been billed yet.
        """
        start_date = gym_today(parent.timezone)

        rows = []
        for item in request.memberships:
            plan_price = plan_prices[(item.plan_id, item.price_id)]
            end_date: date | None = None
            is_recurring = (
                PlanType(plan_price["plan_type"]) == PlanType.recurring
            )
            if (
                not is_recurring
                and plan_price["duration_amount"]
                and plan_price["duration_unit"]
            ):
                end_date = self._calculate_end_date(
                    start_date,
                    plan_price["duration_amount"],
                    plan_price["duration_unit"],
                )
            rows.append({
                "member_id": item.member_id,
                "gym_id": request.gym_id,
                "plan_id": item.plan_id,
                "price_id": item.price_id,
                "start_date": start_date,
                "end_date": end_date,
                "last_paid_date": start_date,
                "next_due_date": None,
                "stripe_item_id": None,
                "prorate": request.prorate,
                "total_price": plan_price["price"],
            })

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
        request: MemberMembershipsBatchStartRequest,
        group: list[_StartItemState],
    ) -> None:
        """Phase C: ONE consolidated invoice sweeps the pending one-time rows.

        The group shares the invoice's fate: an exception means nothing was
        billed (per-step Stripe idempotency) → the whole group fails and is
        cleaned up. After a successful charge an unconfirmed writeback marks
        the row failed but KEEPS it — its line is billed; never un-bill.
        """
        try:
            await self._payment_sync_one_time.charge_one_time(
                request.payer_member_id,
                idempotency_key=uuid5(
                    request.idempotency_key, ONE_TIME_KEY_NAME,
                ),
                paid_with_cash=request.paid_with_cash,
            )
        except Exception as exc:
            await self._fail_group(
                group, f"one-time invoice failed: {exc}", cleanup=True,
            )
            return
        await self._verify_group(group, keep_unverified=True)

    async def _converge_recurring_group(
        self,
        request: MemberMembershipsBatchStartRequest,
        group: list[_StartItemState],
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
                    request.idempotency_key, RECURRING_KEY_NAME,
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
        group: list[_StartItemState],
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
            state.status = MemberMembershipsBatchStartStatus.failed
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
        group: list[_StartItemState],
        error: str,
        cleanup: bool,
    ) -> None:
        """Mark every state in the group failed; optionally clean its rows."""
        for state in group:
            state.status = MemberMembershipsBatchStartStatus.failed
            state.error = error
        if cleanup:
            await self._cleanup_states(group)

    async def _cleanup_states(
        self,
        states: list[_StartItemState],
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

    async def _preview_one_time(
        self,
        stripe_customer_id: str,
        stripe_price_id: str,
        gym_id: UUID,
    ) -> PreviewInvoice:
        """Preview the invoice for a non-recurring plan."""
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(gym_id)
        request = PaymentsInvoicePaymentPreviewRequest(
            stripe_customer_id=stripe_customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=stripe_price_id)],
        )
        return await self._payment_service.preview_invoice_payment(
            request,
            stripe_account_id,
        )

