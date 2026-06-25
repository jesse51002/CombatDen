"""Membership lifecycle operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsChargeCardRequest,
    MemberMembershipsStartPreviewResponse,
    MemberMembershipsStartRequest,
    MemberMembershipsStartResponse,
    MembersBillingLinkCheckResponse,
    PayerInvoiceChange,
)
from src.memberships.service.memberships_cancel import (
    MemberMembershipsCancel,
)
from src.memberships.service.memberships_charge_card import (
    MemberMembershipsChargeCard,
)
from src.memberships.service.memberships_discounts import (
    MemberMembershipsDiscounts,
)
from src.memberships.service.memberships_freeze import (
    MemberMembershipsFreeze,
)
from src.memberships.service.memberships_linked import (
    MemberMembershipsLinked,
)
from src.memberships.service.memberships_mark_paid_cash import (
    MemberMembershipsMarkPaidCash,
)
from src.memberships.service.memberships_start import (
    MemberMembershipsStart,
)
from src.memberships.service.memberships_start_preview import (
    MemberMembershipsStartPreview,
)
from src.memberships.service.memberships_start_validation import (
    MemberMembershipsStartValidation,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.discounts.service.discounts_service import (
        DiscountsService,
    )
    from src.members.service.management.members_management_service import (
        MembersManagementService,
    )
    from src.memberships.service.memberships_reprice import (
        MemberMembershipsReprice,
    )
    from src.memberships.service.memberships_upgrade import (
        MemberMembershipsUpgrade,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.gym_stripe_service import GymStripeService
    from src.shared.payer_resolver import PayerResolver
    from src.shared.paying_member_lock import PayingMemberLock
    from src.sync.service.sync_freeze import (
        PaymentSyncFreeze,
    )
    from src.sync.service.sync_one_time import (
        PaymentSyncOneTime,
    )
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )
    from src.waivers.service.waivers.waivers_service import (
        WaiversService,
    )


class MemberMembershipsService:
    """Membership lifecycle operations (facade).

    Delegates to focused sub-services for cancel, freeze,
    start, and reprice operations. Knows nothing about tasks — the reprice
    REQUEST (create a tracked task) is orchestrated above the facade, in the
    router; the facade exposes only the pure membership preview.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        payment_service: PaymentsStripePaymentService,
        gym_stripe_service: GymStripeService,
        payer_resolver: PayerResolver,
        freeze_service: PaymentSyncFreeze,
        paying_lock: PayingMemberLock,
        payment_sync_one_time: PaymentSyncOneTime,
        discounts_service: DiscountsService,
        reprice_service: MemberMembershipsReprice,
        upgrade_service: MemberMembershipsUpgrade,
        members_management_service: MembersManagementService,
        waivers_service: WaiversService,
    ) -> None:
        # Every lifecycle op is wrapped in the payer concurrency lock (held
        # across its pre-sync + DB write + sync) so no two ops converge the
        # same payer's subscription at once. Item-scoped ops lock the ROW's
        # payer (paid_by_member_id — immutable, so reading it before locking
        # is race-free). EXCEPTION: link / unlink lock TWO accounts (member +
        # parent) themselves, so the facade delegates them bare —
        # PayingMemberLock is non-reentrant, and a nested same-key acquire
        # here would deadlock to LockBusyError.
        self._db_pool = db_pool
        self._paying_lock = paying_lock
        # The reprice + upgrade ops are standalone and take their own family
        # lock; the facade delegates to them bare (like update_price).
        self._reprice = reprice_service
        self._upgrade = upgrade_service
        deps = (
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._cancel = MemberMembershipsCancel(*deps)
        self._freeze = MemberMembershipsFreeze(
            *deps,
            payer_resolver=payer_resolver,
            freeze_service=freeze_service,
        )
        self._update_discounts = MemberMembershipsDiscounts(*deps)
        # Start + its preview share ONE validation instance so they can
        # never drift on what a valid request is.
        self._start_validation = MemberMembershipsStartValidation(
            *deps,
            payer_resolver=payer_resolver,
        )
        self._start = MemberMembershipsStart(
            *deps,
            payment_sync_one_time=payment_sync_one_time,
            update_discounts=self._update_discounts,
            discounts_service=discounts_service,
            validation=self._start_validation,
            members_management_service=members_management_service,
        )
        self._start_preview = MemberMembershipsStartPreview(
            *deps,
            payment_sync_one_time=payment_sync_one_time,
            update_discounts=self._update_discounts,
            discounts_service=discounts_service,
            validation=self._start_validation,
        )
        self._mark_paid_cash = MemberMembershipsMarkPaidCash(
            *deps,
            payment_service=payment_service,
            payer_resolver=payer_resolver,
        )
        self._charge_card = MemberMembershipsChargeCard(
            *deps,
            payment_service=payment_service,
            payer_resolver=payer_resolver,
        )
        # link / unlink is a pure DB change (no sync) and owns its OWN two-family
        # locking, so it takes db_pool + the lock — not the sync deps above —
        # plus the waivers service (authorizing a payer signs the gym's default
        # authorized-payer waiver in the same transaction).
        self._linked = MemberMembershipsLinked(
            db_pool,
            paying_lock,
            waivers_service,
        )

    # ── Cancel ─────────────────────────────────────────────────

    async def cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> date:
        """Cancel ONE active recurring membership (single-item convenience).

        A thin wrapper over :meth:`cancel_many` — the list path is the one
        real implementation. Returns the resolved ``cancel_date`` (the date
        through which the membership remains active).
        """
        dates = await self.cancel_many(
            [item_id], member_id, idempotency_key,
        )
        return dates[item_id]

    async def cancel_many(
        self,
        item_ids: list[UUID],
        member_id: UUID,
        idempotency_key: UUID,
    ) -> dict[UUID, date]:
        """Cancel ONE OR MORE of ``member_id``'s recurring memberships.

        A member's memberships may be funded by different payers, so the lock
        is taken over EVERY distinct payer of the passed items (the sub-service
        then converges each payer's subscription once, under its own derived
        idempotency key). Returns a map of each input ``item_id`` → its resolved
        ``cancel_date``. An empty ``item_ids`` is a no-op (empty map).
        """
        if not item_ids:
            return {}
        payer_ids = await self._get_payers_for_items(item_ids, member_id)
        async with self._paying_lock.lock(payer_ids):
            return await self._cancel.cancel(
                item_ids, member_id, idempotency_key,
            )

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> list[PayerInvoiceChange]:
        """Preview cancelling ONE membership (single-item convenience).

        A thin wrapper over :meth:`preview_cancel_many` — a single cancel is
        one payer → a one-entry list.
        """
        return await self.preview_cancel_many([item_id], member_id)

    async def preview_cancel_many(
        self,
        item_ids: list[UUID],
        member_id: UUID,
    ) -> list[PayerInvoiceChange]:
        """Preview cancelling ONE OR MORE of ``member_id``'s memberships.

        Locks every distinct payer of the passed items, then returns the
        per-payer cost preview (one entry per payer that funds any of them —
        a member's memberships split across payers yield several entries).
        An empty ``item_ids`` is a no-op (empty list).
        """
        if not item_ids:
            return []
        payer_ids = await self._get_payers_for_items(item_ids, member_id)
        async with self._paying_lock.lock(payer_ids):
            return await self._cancel.preview_cancel(item_ids, member_id)

    async def end_one_time(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> date:
        """End a one-time / trial membership early (set ``end_date`` = today).

        Delegated BARE — no payer lock: a one-time / trial membership is a
        terminal invoice with no subscription line, so ending it is a pure DB
        date write (no Stripe converge, nothing for a concurrent sync to race).
        Recurring memberships use ``cancel`` instead.
        """
        return await self._cancel.end_one_time(item_id, member_id)

    # ── Freeze / Unfreeze ──────────────────────────────────────

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
    ) -> None:
        """Freeze a payer's billing (their own subscription)."""
        async with self._paying_lock.lock([member_id]):
            await self._freeze.freeze(
                member_id, gym_id, freeze_months, idempotency_key,
            )

    async def unfreeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Unfreeze a payer's billing (their own subscription)."""
        async with self._paying_lock.lock([member_id]):
            await self._freeze.unfreeze(member_id, gym_id, idempotency_key)

    # ── Start ──────────────────────────────────────────────────

    async def start(
        self,
        request: MemberMembershipsStartRequest,
    ) -> MemberMembershipsStartResponse:
        """Start the request's memberships (one call, one payer, ≤2 charges).

        Locks the payer plus every member in the request — the payer key
        serializes billing; locking the covered members too keeps the
        link-state validation race-free against a concurrent link/unlink
        (which locks those same member ids).
        """
        member_ids = [request.payer_member_id] + [
            item.member_id for item in request.memberships
        ]
        async with self._paying_lock.lock(member_ids):
            return await self._start.start(request)

    async def preview_start(
        self,
        request: MemberMembershipsStartRequest,
    ) -> MemberMembershipsStartPreviewResponse:
        """Preview what starting the request's memberships would charge."""
        member_ids = [request.payer_member_id] + [
            item.member_id for item in request.memberships
        ]
        async with self._paying_lock.lock(member_ids):
            return await self._start_preview.preview(request)

    # ── Mark Paid (Cash) ───────────────────────────────────────

    async def mark_paid_cash(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Mark a recurring membership's open Stripe invoice as paid via cash."""
        payer_id = await self._get_payer_for_item(item_id)
        async with self._paying_lock.lock([payer_id]):
            await self._mark_paid_cash.mark_paid_cash(
                item_id, member_id, idempotency_key,
            )

    # ── Charge Card (ad-hoc amount) ────────────────────────────

    async def charge_card(
        self,
        request: MemberMembershipsChargeCardRequest,
    ) -> None:
        """Charge the request's explicit payer for an ad-hoc amount."""
        async with self._paying_lock.lock([request.paid_by_member_id]):
            await self._charge_card.charge_card(request)

    # ── Reprice (single, direct — NOT a task) ──────────────────
    #
    # The member-detail upgrade is a direct, synchronous reprice (like
    # cancel) — tasks are only for the per-plan BATCH, orchestrated in the
    # router via the tasks layer. The op takes its own family lock.

    async def update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        proration_behavior: ProrationBehavior = (
            ProrationBehavior.no_charge
        ),
    ) -> UUID:
        """Reprice ONE membership to its plan's active price; returns the
        successor row id (== ``item_id`` when it was already on the price)."""
        return await self._reprice.reprice(
            member_id=member_id,
            old_item_id=item_id,
            proration_behavior=proration_behavior,
        )

    # ── Upgrade (cross-plan, charge the prorated difference) ───
    #
    # Move a membership to a DIFFERENT plan's active price and charge the
    # prorated difference now (downgrade charges nothing). A direct,
    # synchronous op like reprice — there is no batch upgrade. The op takes
    # its own family lock, so the facade delegates bare.

    async def upgrade(
        self,
        item_id: UUID,
        member_id: UUID,
        target_plan_id: UUID,
        proration_behavior: ProrationBehavior,
        idempotency_key: UUID,
    ) -> UUID:
        """Upgrade ONE membership to ``target_plan_id``'s active price; returns
        the successor row id."""
        return await self._upgrade.upgrade(
            member_id=member_id,
            old_item_id=item_id,
            target_plan_id=target_plan_id,
            proration_behavior=proration_behavior,
            idempotency_key=idempotency_key,
        )

    async def upgrade_preview(
        self,
        item_id: UUID,
        member_id: UUID,
        target_plan_id: UUID,
        proration_behavior: ProrationBehavior,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what upgrading to ``target_plan_id`` would charge now."""
        return await self._upgrade.upgrade_preview(
            member_id=member_id,
            old_item_id=item_id,
            target_plan_id=target_plan_id,
            proration_behavior=proration_behavior,
        )

    # ── Apply Discounts (add / remove applied-discount rows) ───────────────

    async def add_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        discount_ids: list[UUID],
        idempotency_key: UUID,
        preview: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Add applied-discount rows, or preview the addition (``preview=True``)."""
        payer_id = await self._get_payer_for_item(item_id)
        async with self._paying_lock.lock([payer_id]):
            return await self._update_discounts.add_discounts(
                item_id=item_id,
                member_id=member_id,
                discount_ids=discount_ids,
                idempotency_key=idempotency_key,
                preview=preview,
            )

    async def remove_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        applied_ids: list[UUID],
        idempotency_key: UUID,
        preview: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Remove applied-discount rows, or preview the removal (``preview=True``)."""
        payer_id = await self._get_payer_for_item(item_id)
        async with self._paying_lock.lock([payer_id]):
            return await self._update_discounts.remove_discounts(
                item_id=item_id,
                member_id=member_id,
                applied_ids=applied_ids,
                idempotency_key=idempotency_key,
                preview=preview,
            )

    # ── Authorized payer (authorize / de-authorize / check) ────
    #
    # Delegated BARE — no ``self._paying_lock.lock(...)`` wrap: these lock TWO
    # accounts (member + payer) internally, and the lock is non-reentrant. They
    # are pure DB changes (no Stripe sync); authorizing also signs the gym's
    # default waiver in the same transaction.

    async def link_account(
        self,
        member_id: UUID,
        payer_member_id: UUID,
        *,
        signer_name: str,
        consent_acknowledged: bool,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> None:
        """Authorize a payer for a member (gated by signing the gym waiver)."""
        await self._linked.link_account(
            member_id,
            payer_member_id,
            signer_name=signer_name,
            consent_acknowledged=consent_acknowledged,
            ip_address=ip_address,
            user_agent=user_agent,
        )

    async def check_link_account(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> MembersBillingLinkCheckResponse:
        """Check whether a payer can be authorized for a member."""
        return await self._linked.check_link_account(
            member_id,
            payer_member_id,
        )

    async def preview_remove_authorization(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> list[PayerInvoiceChange]:
        """Cost preview for removing the (member, payer) authorization.

        Pair-scoped: always returns ONE entry for ``payer_member_id``.
        ``affected`` is True iff that payer funds any of ``member_id``'s live
        recurring memberships — in which case ``preview`` is their subscription
        recurring current → new — and False when the removal cancels nothing for
        them (no billing change). Same per-payer cancel preview a single cancel
        uses.
        """
        rows = await self._pair_cancellable(member_id, payer_member_id)
        items = [
            (UUID(str(row["item_id"])), UUID(str(row["member_id"])))
            for row in rows
        ]
        async with self._paying_lock.lock([payer_member_id]):
            return [
                await self._cancel.preview_payer_change(
                    items, payer_member_id
                )
            ]

    async def remove_authorization(
        self,
        member_id: UUID,
        payer_member_id: UUID,
        idempotency_key: UUID,
    ) -> dict[UUID, date]:
        """Remove the (member, payer) authorization, cascading a cancel.

        Pair-scoped and billing-critical: under the two-account lock, cancels
        every live recurring membership ``payer_member_id`` funds for
        ``member_id`` in ONE converge (the cancel list path — one payer sync),
        then deletes the ``member_authorized_payers`` row (the signature audit
        row persists). Memberships paid by other payers, and this payer's
        memberships for other members, are untouched.

        ``idempotency_key`` is the caller-supplied, stable key for this action;
        it threads straight into the cancel path (which derives the payer's
        Stripe sub-key from it deterministically), so a retry of the same
        remove-authorization dedups at Stripe rather than minting a fresh key.

        Locks BOTH accounts itself (like link/unlink), so the facade does NOT
        wrap this in another lock.

        The cancel (Stripe + ``cancel_date``, committed inside the cancel path)
        and the authorization DELETE run in separate transactions — Stripe work
        cannot share a DB transaction — so a DELETE that fails after a successful
        cancel leaves the authorization row behind. This is **idempotent on
        retry**: a retry passes the existence pre-check, finds no remaining
        cancellable memberships, and still runs the DELETE, converging the
        state — a transient failure self-heals rather than stranding a zombie
        authorization.

        Returns the cascading cancel's outcome — the same ``item_id ->
        cancel_date`` map ``cancel`` returns (empty when the relationship funds
        nothing), so the caller can show which memberships were cancelled, exactly
        like a direct cancel.

        Raises:
            ValueError: If no such authorization exists.
            PartialCancelError: If the cascading cancel partially applied (one
                payer converged, a later one failed) — propagated from the cancel
                path so the caller can surface the succeeded/failed split. The
                ``member_authorized_payers`` row is left intact (the delete runs
                only after a full cancel).
        """
        async with self._paying_lock.lock([member_id, payer_member_id]):
            # Fast-fail BEFORE any Stripe cancel: if the authorization is already
            # gone, reject now rather than cancelling the memberships and only
            # then discovering the row is missing (which would commit Stripe
            # cancels for a de-authorize that ultimately "fails"). We hold the
            # lock, so the row cannot vanish between this check and the delete.
            if not await self._authorization_exists(member_id, payer_member_id):
                raise ValueError(
                    f"Payer {payer_member_id} is not an authorized payer "
                    f"for member {member_id}",
                )
            rows = await self._pair_cancellable(member_id, payer_member_id)
            item_ids = [UUID(str(row["item_id"])) for row in rows]
            cancel_dates: dict[UUID, date] = {}
            if item_ids:
                cancel_dates = await self._cancel.cancel(
                    item_ids, member_id, idempotency_key,
                )
            del_sql = load_sql(
                SQL_DIR / "member_authorized_payers_delete.sql",
            )
            async with self._db_pool.session() as session:
                result = await session.execute(
                    text(del_sql),
                    {
                        "member_id": str(member_id),
                        "payer_member_id": str(payer_member_id),
                    },
                )
                if not result.mappings().fetchone():
                    raise ValueError(
                        f"Payer {payer_member_id} is not an authorized payer "
                        f"for member {member_id}",
                    )
                await session.commit()
        return cancel_dates

    # ── Private ────────────────────────────────────────────────

    async def _authorization_exists(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> bool:
        """Whether payer_member_id is currently an authorized payer for
        member_id (the pre-check before a cascading de-authorize)."""
        sql = load_sql(SQL_DIR / "member_authorized_payers_exists.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "payer_member_id": str(payer_member_id),
                },
            )
            return result.mappings().fetchone() is not None

    async def _pair_cancellable(
        self,
        member_id: UUID,
        payer_member_id: UUID,
    ) -> list[dict]:
        """The payee's live recurring memberships funded by this payer."""
        sql = load_sql(
            SQL_DIR / "member_memberships_by_authorization_pair.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "payer_member_id": str(payer_member_id),
                },
            )
            return [dict(row) for row in result.mappings().all()]

    async def _get_payer_for_item(self, item_id: UUID) -> UUID:
        """The membership row's payer — the lock key for item-scoped ops.

        ``paid_by_member_id`` is immutable, so reading it before taking the
        lock is race-free (changing the payer is cancel-old + insert-new).

        Raises:
            ValueError: If the membership row does not exist.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_payer.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"item_id": str(item_id)},
            )
            row = result.fetchone()
        if not row:
            raise ValueError(f"Membership not found: item_id={item_id}")
        return UUID(str(row[0]))

    async def _get_payers_for_items(
        self,
        item_ids: list[UUID],
        member_id: UUID,
    ) -> list[UUID]:
        """The DISTINCT payers of a batch of membership rows — the lock keys
        for a multi-item cancel/preview.

        Scoped to items ``member_id`` is entitled to — its own or ones it pays
        for, the same subject-or-payer rule ``_get_membership`` enforces — so an
        item_id the actor isn't authorized for is rejected HERE, before the
        billing lock is taken; it never locks an unrelated payer's subscription.
        ``paid_by_member_id`` is immutable, so reading it before locking is
        race-free. Every passed item must resolve (a stale or unauthorized
        item_id is a caller error, not a silent skip).

        Raises:
            ValueError: If any ``item_id`` does not exist or is not the actor's.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_payers.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "item_ids": [str(i) for i in item_ids],
                    "member_id": str(member_id),
                },
            )
            rows = result.mappings().all()
        payers = {
            UUID(str(row["item_id"])): UUID(str(row["paid_by_member_id"]))
            for row in rows
        }
        missing = [i for i in item_ids if i not in payers]
        if missing:
            raise ValueError(
                f"Membership not found: item_ids={missing}",
            )
        return list(dict.fromkeys(payers.values()))
