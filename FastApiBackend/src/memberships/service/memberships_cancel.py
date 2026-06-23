"""Cancel a member's recurring membership (DB-first, verified)."""

import logging
from datetime import date
from uuid import UUID

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
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

logger = logging.getLogger(__name__)


class MemberMembershipsCancel(MemberMembershipsBase):
    """Cancel a specific active recurring membership."""

    async def cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
    ) -> date:
        """Cancel a specific active recurring membership (DB-first, verified).

        Writes ``cancel_date`` FIRST (status stays ``applied``), then runs the
        param-less sync, which re-derives the desired state (the cancelled row is
        excluded by the read), removes the line from Stripe, and stamps the row
        ``deleted``. The cancel is then **verified**: if the sync did not confirm
        on Stripe (the row was not stamped ``deleted``), the cancel is reverted by
        clearing ``cancel_date``. This works because ``cancel_date`` only locks
        once the membership is actually removed from Stripe (``deleted``) — while
        the cancel is unconfirmed it stays clearable, so no transient status is
        staged. ``stripe_item_id`` is left intact (historical invoice-line
        record).

        If the membership is already cancelled, this is a no-op.

        Args:
            item_id: The membership item.
            member_id: The member.
            idempotency_key: Caller-supplied key scoped to this cancel.

        Returns:
            The resolved ``cancel_date``.

        Raises:
            ValueError: If the membership is not found, has already
                ended, or is non-recurring.
            SyncNotConfirmedError: If the cancel could not be confirmed on
                Stripe (the DB change has been reverted).
        """
        row = await self._get_membership(item_id, member_id)

        if row["cancel_date"] is not None:
            return row["cancel_date"]

        self._validate_cancel(row, item_id, member_id)

        # ── DB-first: set cancel_date (status stays 'applied'), THEN converge ──
        cancel_date = await self._crm_cancel(
            item_id,
            member_id,
            gym_today(row["timezone"]),
        )

        payer_member_id = row["paid_by_member_id"]

        async def _sync() -> None:
            try:
                await self._payment_sync.update_payments_recurring(
                    payer_member_id,
                    idempotency_key=idempotency_key,
                    proration_behavior=ProrationBehavior.no_charge,
                )
            except PaymentsResourceNotFoundError:
                # Stripe no longer has the line — the cancel is already true on
                # Stripe's side. Record it deleted so the verify passes; the
                # cancel stands.
                logger.warning(
                    "Stripe resource not found during cancel (line already "
                    "gone); marking deleted: item_id=%s, member_id=%s",
                    item_id,
                    member_id,
                )
                await self._mark_deleted(item_id)

        async def _verify() -> bool:
            status = await self._get_sync_status(item_id, member_id)
            return status == StripeSyncStatus.deleted

        await sync_or_revert(
            sync_fn=_sync,
            revert_fn=lambda: self._uncancel(item_id, member_id),
            entity_name="member_membership",
            crm_pk=str(item_id),
            verify_fn=_verify,
        )
        return cancel_date

    async def preview_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what cancelling a membership would charge.

        Runs every validation ``cancel`` runs (membership lookup,
        already-cancelled short-circuit, recurring-plan guard) and
        then calls the Stripe invoice preview. Returns ``None`` if
        the membership is already cancelled.

        Raises:
            ValueError: Same conditions as ``cancel``.
        """
        row = await self._get_membership(item_id, member_id)

        if row["cancel_date"] is not None:
            return None

        self._validate_cancel(row, item_id, member_id)

        # Self-heal: restore any stale preview_remove/preview_add rows for this
        # payer left by a prior crashed preview, before staging our own.
        await self._sweep_stale_preview_rows(row["paid_by_member_id"])

        # Stage the membership 'preview_remove' so the preview build drops it
        # (preview=True excludes preview_remove), then restore 'applied'. The
        # window is bounded by `finally`; the per-payer lock (#25) closes the
        # race vs a concurrent real sync (TODO).
        return await staged_preview(
            stage_fn=lambda: self._set_sync_status(
                item_id, member_id, StripeSyncStatus.preview_remove
            ),
            cleanup_fn=lambda: self._set_sync_status(item_id, member_id, StripeSyncStatus.applied),
            preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                row["paid_by_member_id"],
                proration_behavior=ProrationBehavior.no_charge,
            ),
        )

    # ── Private ────────────────────────────────────────────────

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

        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            logger.warning(
                f"Recurring membership has ended set. "
                f"Shouldn't be possible "
                f"(end_date={row['end_date']}): "
                f"item_id={item_id}, member_id={member_id}"
            )

    async def _crm_cancel(
        self,
        item_id: UUID,
        member_id: UUID,
        today: date,
    ) -> date:
        """Set ``cancel_date`` in the CRM database (status stays ``applied``).

        Returns the resolved ``cancel_date`` (the date through which the
        membership remains active). Only writes ``cancel_date`` —
        ``stripe_item_id`` is left intact as the historical invoice-line record.
        """
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
        """Revert a cancel whose sync did not confirm: clear ``cancel_date``.

        Permitted while the membership has not been removed from Stripe yet
        (status is not ``deleted``) — the exact revert case. Status is left
        ``applied``; ``stripe_item_id`` is left intact.
        """
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
        sql = load_sql(
            SQL_DIR / "payment_sync" / "mark_membership_deleted.sql",
        )
        async with self._db_pool.session() as session:
            await session.execute(text(sql), {"item_ids": [str(item_id)]})
            await session.commit()
