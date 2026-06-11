"""Membership lifecycle operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

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
from src.memberships.service.memberships_update_price import (
    MemberMembershipsUpdatePrice,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.database import DirectDatabasePool

if TYPE_CHECKING:
    from src.discounts.service.discounts_service import (
        DiscountsService,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.billing_parent_resolver import BillingParentResolver
    from src.shared.gym_stripe_service import GymStripeService
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
    from src.tasks.service.tasks_executor import TasksExecutor
    from src.tasks.service.tasks_service import TasksService


class MemberMembershipsService:
    """Membership lifecycle operations (facade).

    Delegates to focused sub-services for cancel, freeze,
    start, and update_price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        payment_service: PaymentsStripePaymentService,
        gym_stripe_service: GymStripeService,
        parent_resolver: BillingParentResolver,
        freeze_service: PaymentSyncFreeze,
        paying_lock: PayingMemberLock,
        payment_sync_one_time: PaymentSyncOneTime,
        discounts_service: DiscountsService,
        tasks_service: TasksService,
        tasks_executor: TasksExecutor,
    ) -> None:
        # Every single-family lifecycle op is wrapped in the paying-parent
        # concurrency lock (held across its pre-sync + DB write + sync) so no two
        # ops sync the same family at once. EXCEPTION: link / unlink lock TWO
        # families (member + paying parent) themselves, so the facade delegates
        # them bare — PayingMemberLock is non-reentrant, and a nested same-family
        # acquire here would deadlock to LockBusyError.
        self._paying_lock = paying_lock
        # The in-task guard: every ITEM-targeted op rejects a membership row
        # referenced by an unfinished task (the family lock only serializes
        # in-flight attempts; a task awaiting retry holds no lock, so the
        # guard is what protects its desired state between attempts).
        # Member-level ops (charge_card, freeze, link) are not item-targeted
        # and stay unguarded.
        self._tasks = tasks_service
        deps = (
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._cancel = MemberMembershipsCancel(*deps)
        self._freeze = MemberMembershipsFreeze(
            *deps,
            parent_resolver=parent_resolver,
            freeze_service=freeze_service,
        )
        self._update_discounts = MemberMembershipsDiscounts(*deps)
        # Start + its preview share ONE validation instance so they can
        # never drift on what a valid request is.
        self._start_validation = MemberMembershipsStartValidation(
            *deps,
            parent_resolver=parent_resolver,
        )
        self._start = MemberMembershipsStart(
            *deps,
            payment_sync_one_time=payment_sync_one_time,
            update_discounts=self._update_discounts,
            discounts_service=discounts_service,
            validation=self._start_validation,
        )
        self._start_preview = MemberMembershipsStartPreview(
            *deps,
            payment_sync_one_time=payment_sync_one_time,
            update_discounts=self._update_discounts,
            discounts_service=discounts_service,
            validation=self._start_validation,
        )
        self._update_price = MemberMembershipsUpdatePrice(
            *deps,
            tasks_service=tasks_service,
            tasks_executor=tasks_executor,
        )
        self._mark_paid_cash = MemberMembershipsMarkPaidCash(
            *deps,
            payment_service=payment_service,
            parent_resolver=parent_resolver,
        )
        self._charge_card = MemberMembershipsChargeCard(
            *deps,
            payment_service=payment_service,
            parent_resolver=parent_resolver,
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

        Raises:
            MembershipInTaskError: If the membership is inside an
                unfinished task.
        """
        await self._tasks.assert_memberships_not_in_task([item_id])
        async with self._paying_lock.lock([member_id]):
            return await self._cancel.cancel(
                item_id, member_id, idempotency_key,
            )

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what cancelling a membership would charge."""
        async with self._paying_lock.lock([member_id]):
            return await self._cancel.preview_cancel(item_id, member_id)

    # ── Freeze / Unfreeze ──────────────────────────────────────

    async def freeze(
        self,
        member_id: UUID,
        gym_id: UUID,
        freeze_months: int,
        idempotency_key: UUID,
    ) -> None:
        """Freeze a member's account (account-level)."""
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
        """Unfreeze a member's account (account-level)."""
        async with self._paying_lock.lock([member_id]):
            await self._freeze.unfreeze(member_id, gym_id, idempotency_key)

    # ── Start ──────────────────────────────────────────────────

    async def start(
        self,
        request: MemberMembershipsStartRequest,
    ) -> MemberMembershipsStartResponse:
        """Start the request's memberships (one call, one family, ≤2 charges).

        Locks the payer plus every member in the request — linked members
        resolve to the payer's family key (the lock dedupes), and locking
        the members too keeps the link-state validation race-free against a
        concurrent link/unlink.
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
        """Mark a recurring membership's open Stripe invoice as paid via cash.

        Raises:
            MembershipInTaskError: If the membership is inside an
                unfinished task.
        """
        await self._tasks.assert_memberships_not_in_task([item_id])
        async with self._paying_lock.lock([member_id]):
            await self._mark_paid_cash.mark_paid_cash(
                item_id, member_id, idempotency_key,
            )

    # ── Charge Card (ad-hoc amount) ────────────────────────────

    async def charge_card(
        self,
        request: MemberMembershipsChargeCardRequest,
    ) -> None:
        """Charge a member's card (or mark as cash) for an ad-hoc amount."""
        async with self._paying_lock.lock([request.member_id]):
            await self._charge_card.charge_card(request)

    # ── Update Price ───────────────────────────────────────────

    async def update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> UUID:
        """Request a reprice onto the plan's active price; returns task_id.

        NO lock wrap: this only validates and creates the tracked
        ``membership_reprice`` task (fired in the background) — the task
        executor takes the family lock itself when it runs.
        """
        return await self._update_price.request_update_price(
            item_id=item_id,
            member_id=member_id,
            prorate=prorate,
        )

    async def preview_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Preview upgrading a membership to the plan's active price."""
        async with self._paying_lock.lock([member_id]):
            return await self._update_price.preview_update_price(
                item_id=item_id,
                member_id=member_id,
                prorate=prorate,
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
        """Add applied-discount rows, or preview the addition (``preview=True``).

        Raises:
            MembershipInTaskError: If the membership is inside an
                unfinished task (previews included — there is nothing
                actionable to preview on a mid-task membership).
        """
        await self._tasks.assert_memberships_not_in_task([item_id])
        async with self._paying_lock.lock([member_id]):
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
        """Remove applied-discount rows, or preview the removal (``preview=True``).

        Raises:
            MembershipInTaskError: If the membership is inside an
                unfinished task (previews included).
        """
        await self._tasks.assert_memberships_not_in_task([item_id])
        async with self._paying_lock.lock([member_id]):
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
    # TWO families (member + paying parent) internally, and the lock is
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
