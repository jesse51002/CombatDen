"""Request a reprice onto the plan's active price (tracked background task).

A reprice is APPEND-ONLY — ``price_id``/``stripe_item_id`` are
trigger-enforced immutable, so the membership row is never mutated. This
service VALIDATES and creates a ``membership_reprice`` task (one item), fires
its execution in the background, and returns the task_id immediately; the CRM
polls ``GET /tasks/{task_id}``. The actual cancel-old + insert-successor +
converge work lives in ``MemberMembershipsRepriceExecutor``.
"""

import logging
from datetime import date
from uuid import UUID

from schema.member_membership import StripeSyncStatus
from schema.task import TaskType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import staged_preview
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql
from src.sync.service.sync_service import PaymentSyncService
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_service import TasksService
from src.tasks.tasks_schema import TaskItemCreate

logger = logging.getLogger(__name__)


class MemberMembershipsUpdatePrice(MemberMembershipsBase):
    """Validate + enqueue a reprice onto the plan's active price tier."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        tasks_service: TasksService,
        tasks_executor: TasksExecutor,
    ) -> None:
        super().__init__(db_pool, payment_sync_service, gym_stripe_service)
        self._tasks = tasks_service
        self._tasks_executor = tasks_executor

    async def request_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> UUID:
        """Validate and enqueue the reprice; returns the task_id (202-style).

        The caller does not choose the target price — the task targets the
        one ``membership_plan_prices`` row with ``is_active = true`` for the
        plan, captured here so the executor reprices exactly what was
        requested. Tasks are only created for a REAL change: a membership
        already on the active price is rejected (no no-op tasks). The
        executor mints its own Stripe idempotency keys per attempt — the
        request-level key is not used by the task flow.

        Raises:
            ValueError: If the membership is not found, cancelled, ended,
                no active price exists for the plan, or the membership is
                already on the active price.
            MembershipInTaskError: If the membership is already inside an
                unfinished task.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )
        target_price_id = UUID(str(active_price["price_id"]))
        if UUID(str(row["price_id"])) == target_price_id:
            raise ValueError(
                f"Membership is already on the plan's active price: "
                f"item_id={item_id}, price_id={target_price_id}"
            )

        # The in-task guard doubles as the double-submit guard: one
        # unfinished reprice per membership.
        await self._tasks.assert_memberships_not_in_task([item_id])

        task_id = await self._tasks.create_task(
            UUID(str(row["gym_id"])),
            TaskType.membership_reprice,
            [
                TaskItemCreate(
                    member_id=member_id,
                    old_item_id=item_id,
                    target_price_id=target_price_id,
                    prorate=prorate,
                ),
            ],
        )
        self._tasks_executor.start_in_background(task_id)
        return task_id

    async def preview_update_price(
        self,
        item_id: UUID,
        member_id: UUID,
        prorate: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Preview repricing a membership to the plan's active price.

        Stages the reprice EXACTLY as the executor would write it, as
        preview-only rows: the old row stamped ``preview_remove``, a
        ``preview_add`` successor at the active price, and ``preview_add``
        copies of the live applied discounts — then reads the engine preview
        and always cleans up (``finally``). ``price_id`` is never touched
        (it is trigger-immutable). Runs under the facade's family lock.

        Raises:
            ValueError: Same validation conditions as
                ``request_update_price``, except already-on-active-price
                previews as-is (nothing to stage).
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_update_price(row, item_id, member_id)

        active_price = await self._get_active_price_for_plan(
            row["gym_id"],
            row["plan_id"],
        )
        proration_behavior = "always_invoice" if prorate else "none"

        if UUID(str(row["price_id"])) == UUID(str(active_price["price_id"])):
            # Already on the active price — nothing to stage; preview as-is.
            return await self._payment_sync.preview_update_payments_recurring(
                member_id,
                proration_behavior=proration_behavior,
            )

        today = gym_today(row["timezone"])
        staged_item_ids: list[UUID] = []

        async def _stage() -> None:
            await self._set_sync_status(
                item_id,
                member_id,
                StripeSyncStatus.preview_remove,
            )
            staged_item_ids.append(
                await self._stage_successor_with_discounts(
                    row,
                    item_id,
                    member_id,
                    active_price,
                    today,
                    prorate,
                )
            )

        async def _cleanup() -> None:
            # FK order: discount copies cascade out with the staged row?
            # No — applied discounts RESTRICT on the membership row, so the
            # copies go first, then the staged pending row, then the old
            # row's status is restored.
            if staged_item_ids:
                await self._delete_preview_discount_copies(staged_item_ids)
                await self._delete_pending(staged_item_ids)
            await self._set_sync_status(
                item_id,
                member_id,
                StripeSyncStatus.applied,
            )

        return await staged_preview(
            stage_fn=_stage,
            cleanup_fn=_cleanup,
            preview_fn=lambda: (
                self._payment_sync.preview_update_payments_recurring(
                    member_id,
                    proration_behavior=proration_behavior,
                )
            ),
        )

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _validate_update_price(
        row: dict,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate a membership can be repriced."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot update price on cancelled membership: "
                f"item_id={item_id}, member_id={member_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            raise ValueError(
                f"Cannot update price on ended membership: "
                f"item_id={item_id}, member_id={member_id}"
            )

    async def _stage_successor_with_discounts(
        self,
        row: dict,
        item_id: UUID,
        member_id: UUID,
        active_price: dict,
        today: date,
        prorate: bool,
    ) -> UUID:
        """Insert the preview successor + its preview discount copies.

        Mirrors the executor's writes one-for-one (same insert SQL, same
        copy SQL) with ``preview_add`` so the engine preview prices exactly
        the state the real reprice would bill.
        """
        inserted = await self._crm_insert([
            {
                "member_id": member_id,
                "gym_id": UUID(str(row["gym_id"])),
                "plan_id": UUID(str(row["plan_id"])),
                "price_id": UUID(str(active_price["price_id"])),
                "start_date": today,
                "end_date": None,
                "last_paid_date": today,
                "next_due_date": None,
                "stripe_item_id": None,
                "prorate": prorate,
                "total_price": active_price["price"],
                "sync_status": StripeSyncStatus.preview_add,
            },
        ])
        staged_id = next(iter(inserted.values()))
        await self._copy_discounts_preview(item_id, staged_id, today)
        return staged_id

    async def _copy_discounts_preview(
        self,
        old_item_id: UUID,
        staged_item_id: UUID,
        today: date,
    ) -> None:
        """Stage preview_add copies of the old row's live applied discounts."""
        sql = load_sql(
            SQL_DIR / "applied_discounts" / "copy_applied_discounts.sql"
        )
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "old_item_id": str(old_item_id),
                    "new_item_id": str(staged_item_id),
                    "gym_today": today,
                    "sync_status": StripeSyncStatus.preview_add.value,
                },
            )
            await session.commit()

    async def _delete_preview_discount_copies(
        self,
        staged_item_ids: list[UUID],
    ) -> None:
        """Delete the staged rows' preview discount copies (FK order)."""
        sql = load_sql(
            SQL_DIR
            / "applied_discounts"
            / "delete_preview_applied_discounts.sql"
        )
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"item_ids": [str(i) for i in staged_item_ids]},
            )
            await session.commit()
