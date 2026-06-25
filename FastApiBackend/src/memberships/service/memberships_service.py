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
        # locking, so it takes only db_pool + the lock — not the sync deps above.
        self._linked = MemberMembershipsLinked(db_pool, paying_lock)

    # ── Cancel ─────────────────────────────────────────────────

    async def cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> date:
        """Cancel a specific active recurring membership.

        Returns the resolved ``cancel_date`` — the date through
        which the membership remains active.
        """
        payer_id = await self._get_payer_for_item(item_id)
        async with self._paying_lock.lock([payer_id]):
            return await self._cancel.cancel(
                item_id, member_id, idempotency_key,
            )

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what cancelling a membership would charge."""
        payer_id = await self._get_payer_for_item(item_id)
        async with self._paying_lock.lock([payer_id]):
            return await self._cancel.preview_cancel(item_id, member_id)

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

    # ── Linked account (link / unlink / check) ─────────────────
    #
    # Delegated BARE — no ``self._paying_lock.lock(...)`` wrap: link / unlink lock
    # TWO accounts (member + parent) internally, and the lock is
    # non-reentrant. These are pure DB changes (no Stripe sync).

    async def link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> None:
        """Link an existing member to a paying parent account."""
        await self._linked.link_account(member_id, parent_member_id)

    async def unlink_account(
        self,
        member_id: UUID,
    ) -> None:
        """Unlink a member from their paying parent account."""
        await self._linked.unlink_account(member_id)

    async def check_link_account(
        self,
        member_id: UUID,
        parent_member_id: UUID,
    ) -> MembersBillingLinkCheckResponse:
        """Check whether a member can be linked to a parent account."""
        return await self._linked.check_link_account(member_id, parent_member_id)

    # ── Private ────────────────────────────────────────────────

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
