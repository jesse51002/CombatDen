"""Cancel a member's recurring membership (DB-first, verified)."""

import logging
from datetime import date
from typing import NoReturn
from uuid import UUID, uuid5

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_exceptions import PartialCancelError
from src.memberships.memberships_schema import PayerInvoiceChange
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.db_first_helpers import staged_preview, sync_or_revert
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql
from src.sync import SQL_DIR as SYNC_SQL_DIR

logger = logging.getLogger(__name__)


class MemberMembershipsCancel(MemberMembershipsBase):
    """Cancel a specific active recurring membership."""

    async def cancel(
        self,
        item_ids: list[UUID],
        member_id: UUID,
        idempotency_key: UUID,
    ) -> dict[UUID, date]:
        """Cancel one or more recurring memberships (DB-first, payer-atomic).

        Processes one payer at a time: writes cancel_dates, converges Stripe,
        then advances. A failure after earlier payers succeeded raises PartialCancelError.
        Returns item_id → resolved cancel_date on full success.
        """
        # 1) Validation — no DB writes. Group cancellable items by payer.
        dates: dict[UUID, date] = {}
        by_payer: dict[UUID, list[tuple[UUID, UUID, date]]] = {}
        for item_id in item_ids:
            row = await self._get_membership(item_id, member_id)
            if row["cancel_date"] is not None:
                dates[item_id] = row["cancel_date"]
                continue
            self._validate_cancel(row, item_id, member_id)
            subject_member_id = UUID(str(row["member_id"]))
            by_payer.setdefault(
                UUID(str(row["paid_by_member_id"])), []
            ).append((item_id, subject_member_id, gym_today(row["timezone"])))

        # 2) Per-payer pass — write cancel_dates then converge, one payer at a time.
        succeeded: dict[UUID, date] = {}
        for payer_member_id, payer_items in by_payer.items():
            payer_keyed_items = [
                (item_id, subject) for item_id, subject, _ in payer_items
            ]
            payer_dates: dict[UUID, date] = {}
            # Clear any cancel_dates we wrote if the write loop fails mid-way
            # (before converge runs — nothing is 'deleted' yet so _uncancel is safe).
            try:
                for item_id, subject, today in payer_items:
                    payer_dates[item_id] = await self._crm_cancel(
                        item_id, subject, today
                    )
            except Exception as exc:
                for item_id, subject in payer_keyed_items:
                    if item_id in payer_dates:
                        await self._uncancel(item_id, subject)
                self._raise_payer_failure(
                    succeeded, payer_member_id, payer_keyed_items, exc
                )
            try:
                await self._converge_cancellations(
                    payer_keyed_items,
                    payer_member_id,
                    # Distinct deterministic key per payer so retries dedup correctly.
                    uuid5(idempotency_key, str(payer_member_id)),
                )
            except Exception as exc:
                self._raise_payer_failure(
                    succeeded, payer_member_id, payer_keyed_items, exc
                )
            succeeded.update(payer_dates)

        dates.update(succeeded)
        return dates

    @staticmethod
    def _raise_payer_failure(
        succeeded: dict[UUID, date],
        payer_member_id: UUID,
        payer_keyed_items: list[tuple[UUID, UUID]],
        exc: Exception,
    ) -> NoReturn:
        """Re-raise raw if no earlier payer succeeded; else wrap in PartialCancelError."""
        if not succeeded:
            raise exc
        raise PartialCancelError(
            succeeded=succeeded,
            failed_payer_id=payer_member_id,
            failed_item_ids=[item_id for item_id, _ in payer_keyed_items],
            cause=exc,
        ) from exc

    async def _converge_cancellations(
        self,
        items: list[tuple[UUID, UUID]],
        payer_member_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Converge one payer's subscription, verify items landed deleted,
        revert any that didn't."""
        item_ids = [item_id for item_id, _ in items]

        async def _sync() -> None:
            try:
                await self._payment_sync.update_payments_recurring(
                    payer_member_id,
                    idempotency_key=idempotency_key,
                    proration_behavior=ProrationBehavior.no_charge,
                )
            except PaymentsResourceNotFoundError:
                # Stripe no longer has the line(s) — the cancel is already true
                # on Stripe's side. Record them deleted so the verify passes.
                logger.warning(
                    "Stripe resource not found during cancel (line already "
                    "gone); marking deleted: item_ids=%s, payer_member_id=%s",
                    item_ids,
                    payer_member_id,
                )
                for item_id in item_ids:
                    await self._mark_deleted(item_id)

        async def _verify() -> bool:
            for item_id, subject in items:
                status = await self._get_sync_status(item_id, subject)
                if status != StripeSyncStatus.deleted:
                    return False
            return True

        async def _revert() -> None:
            for item_id, subject in items:
                status = await self._get_sync_status(item_id, subject)
                if status != StripeSyncStatus.deleted:
                    await self._uncancel(item_id, subject)

        await sync_or_revert(
            sync_fn=_sync,
            revert_fn=_revert,
            entity_name="member_membership",
            crm_pk=",".join(str(i) for i in item_ids),
            verify_fn=_verify,
        )

    async def preview_cancel(
        self,
        item_ids: list[UUID],
        member_id: UUID,
    ) -> list[PayerInvoiceChange]:
        """Preview cancel for one or more memberships; returns per-payer current→new. Read-only."""
        by_payer: dict[UUID, list[tuple[UUID, UUID]]] = {}
        for item_id in item_ids:
            row = await self._get_membership(item_id, member_id)
            if row["cancel_date"] is not None:
                continue
            self._validate_cancel(row, item_id, member_id)
            subject_member_id = UUID(str(row["member_id"]))
            by_payer.setdefault(
                UUID(str(row["paid_by_member_id"])), []
            ).append((item_id, subject_member_id))
        return [
            await self.preview_payer_change(payer_items, payer)
            for payer, payer_items in by_payer.items()
        ]

    async def preview_payer_change(
        self,
        items: list[tuple[UUID, UUID]],
        payer_member_id: UUID,
    ) -> PayerInvoiceChange:
        """Build one payer's preview entry (affected=True if any items are being cancelled)."""
        affected = len(items) > 0
        preview = (
            await self._staged_cancel_preview(items, payer_member_id)
            if affected
            else None
        )
        names = await self._payer_names([payer_member_id])
        first, last = names.get(payer_member_id, ("", ""))
        return PayerInvoiceChange(
            payer_member_id=payer_member_id,
            payer_first_name=first,
            payer_last_name=last,
            affected=affected,
            preview=preview,
        )

    async def end_one_time(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> date:
        """End a one-time/trial membership early (pure DB write). Returns
        the resolved termination date.

        A HUMAN-initiated termination, so it writes ``cancel_date`` — never
        ``end_date``, which is automatic-only by convention (the depletion
        auto-end + the purchase-stamped duration expiry). The split keeps a
        staff-ended pack safe from the check-in reversal's un-end, which
        only ever touches ``end_date``.
        """
        row = await self._get_membership(item_id, member_id)
        # One gym-local ``today`` for BOTH the guard and the cancel_date
        # write, so they can't straddle midnight (validate on day N, end on
        # day N+1).
        today = gym_today(row["timezone"])
        self._validate_end_one_time(row, item_id, member_id, today)

        sql = load_sql(SQL_DIR / "member_memberships_end.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "item_id": str(item_id),
                    # Use the row's actual subject, not the request actor (payer may differ).
                    "member_id": str(row["member_id"]),
                    "gym_today": today,
                },
            )
            terminated_on = result.scalar_one()
            await session.commit()
        return terminated_on

    # ── Private ────────────────────────────────────────────────

    async def _payer_names(
        self,
        payer_member_ids: list[UUID],
    ) -> dict[UUID, tuple[str, str]]:
        """Return (first_name, last_name) for each payer id."""
        sql = load_sql(SQL_DIR / "member_names_by_ids.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(i) for i in payer_member_ids]},
            )
            return {
                UUID(str(row["member_id"])): (
                    row["first_name"],
                    row["last_name"],
                )
                for row in result.mappings().all()
            }

    async def _staged_cancel_preview(
        self,
        items: list[tuple[UUID, UUID]],
        payer_member_id: UUID,
    ) -> DueNowVsRecurringPreview | None:
        """Stage items preview_remove, preview the payer's subscription, restore original statuses.

        Self-heals stale preview rows first. Restores pre-stage status verbatim
        (not blindly ``applied`` — an item may be ``not_added``).
        """
        await self._sweep_stale_preview_rows(payer_member_id)

        # Capture statuses before staging so cleanup restores them verbatim.
        originals: dict[tuple[UUID, UUID], StripeSyncStatus] = {}
        for item_id, member_id in items:
            status = await self._get_sync_status(item_id, member_id)
            if status is not None:
                originals[(item_id, member_id)] = status

        async def _stage() -> None:
            for item_id, member_id in items:
                await self._set_sync_status(
                    item_id, member_id, StripeSyncStatus.preview_remove
                )

        async def _cleanup() -> None:
            for item_id, member_id in items:
                original = originals.get((item_id, member_id))
                if original is None:
                    continue  # Row vanished between capture and cleanup.
                await self._set_sync_status(item_id, member_id, original)

        return await staged_preview(
            stage_fn=_stage,
            cleanup_fn=_cleanup,
            preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                payer_member_id,
                proration_behavior=ProrationBehavior.no_charge,
            ),
        )

    @staticmethod
    def _validate_end_one_time(
        row: dict,
        item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> None:
        """Validate a one-time / trial membership can be ended early."""
        if row["plan_type"] == PlanType.recurring:
            raise ValueError(
                f"Cannot end a recurring membership here — use cancel: "
                f"item_id={item_id}, member_id={member_id}"
            )
        # Any cancel_date blocks ending — the pack was already manually
        # terminated (this op's own write IS a cancel_date).
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot end a membership with a pending cancellation "
                f"— clear the cancellation first: "
                f"item_id={item_id}, member_id={member_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= today:
            raise ValueError(
                f"Membership already ended: "
                f"item_id={item_id}, member_id={member_id}"
            )

    @staticmethod
    def _validate_cancel(
        row: dict,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate a membership can be cancelled."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Cannot cancel non-recurring membership "
                f"(plan_type={row['plan_type']}): "
                f"item_id={item_id}, member_id={member_id}"
            )

        if row["end_date"] is not None and row["end_date"] <= gym_today(
            row["timezone"]
        ):
            # Already-past end_date means the Stripe item is gone — reject cleanly.
            raise ValueError(
                f"Cannot cancel an already-ended recurring membership "
                f"(end_date={row['end_date']}): "
                f"item_id={item_id}, member_id={member_id}"
            )

    async def _crm_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> date:
        """Set cancel_date (status stays applied; stripe_item_id unchanged).
        Returns the resolved date."""
        cancel_sql = load_sql(SQL_DIR / "member_memberships_cancel.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
            "gym_today": today,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(cancel_sql), params)
            cancel_date = result.scalar_one()
            await session.commit()
        return cancel_date

    async def _uncancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Clear cancel_date when sync did not confirm (membership not yet deleted)."""
        sql = load_sql(SQL_DIR / "member_memberships_uncancel.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _mark_deleted(self, item_id: UUID) -> None:
        """Stamp a membership ``deleted`` (its Stripe line is already gone)."""
        sql = load_sql(SYNC_SQL_DIR / "mark_membership_deleted.sql")
        async with self._db_pool.session() as session:
            await session.execute(text(sql), {"item_ids": [str(item_id)]})
            await session.commit()
