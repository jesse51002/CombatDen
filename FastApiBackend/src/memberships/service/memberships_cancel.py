"""Cancel a member's recurring membership (DB-first, verified)."""

import logging
from datetime import date
from uuid import UUID, uuid5

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
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

logger = logging.getLogger(__name__)


class MemberMembershipsCancel(MemberMembershipsBase):
    """Cancel a specific active recurring membership."""

    async def cancel(
        self,
        item_ids: list[UUID],
        member_id: UUID,
        idempotency_key: UUID,
    ) -> dict[UUID, date]:
        """Cancel ONE OR MORE of a member's recurring memberships (DB-first,
        verified). Natively single or many — a single cancel is just a
        one-element list.

        Sets each row's ``cancel_date`` FIRST (status stays ``applied``), then
        **batches the converge BY PAYER**: a member's memberships may be funded
        by different payers, so each distinct payer's subscription is converged
        ONCE (re-derives the desired state with the cancelled rows excluded,
        removes the lines, stamps them ``deleted``), under its own idempotency
        key. ``cancel_date`` only locks once a row is actually removed from
        Stripe (``deleted``); while unconfirmed it stays clearable, so a payer's
        converge that does not confirm is reverted (its cancel_dates cleared)
        independently. ``stripe_item_id`` is left intact (historical
        invoice-line record). Already-cancelled items are a no-op.

        Returns a map of every input ``item_id`` → its resolved ``cancel_date``.

        Raises:
            ValueError: If a membership is not found, has ended, or is
                non-recurring.
            SyncNotConfirmedError: If a payer's converge could not be confirmed
                (that payer's cancel_dates have been reverted).
        """
        dates: dict[UUID, date] = {}
        by_payer: dict[UUID, list[UUID]] = {}
        for item_id in item_ids:
            row = await self._get_membership(item_id, member_id)
            if row["cancel_date"] is not None:
                dates[item_id] = row["cancel_date"]
                continue
            self._validate_cancel(row, item_id, member_id)
            dates[item_id] = await self._crm_cancel(
                item_id, member_id, gym_today(row["timezone"])
            )
            by_payer.setdefault(
                UUID(str(row["paid_by_member_id"])), []
            ).append(item_id)
        for payer_member_id, payer_items in by_payer.items():
            await self._converge_cancellations(
                payer_items,
                member_id,
                payer_member_id,
                # Distinct, deterministic key per payer's subscription update so
                # the per-payer Stripe ops never collide on one idempotency key
                # (and a retry derives the same per-payer keys).
                uuid5(idempotency_key, str(payer_member_id)),
            )
        return dates

    async def _converge_cancellations(
        self,
        item_ids: list[UUID],
        member_id: UUID,
        payer_member_id: UUID,
        idempotency_key: UUID,
    ) -> None:
        """Run ONE payer sync to drop the now-``cancel_date``'d [item_ids], verify
        every one landed ``deleted``, and revert (uncancel) any that did not.

        One converge per distinct payer — ``cancel`` calls this once per payer
        it batches; one sync re-derives that payer's desired state with all
        their cancelled rows excluded and converges Stripe once.
        """

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
                    "gone); marking deleted: item_ids=%s, member_id=%s",
                    item_ids,
                    member_id,
                )
                for item_id in item_ids:
                    await self._mark_deleted(item_id)

        async def _verify() -> bool:
            for item_id in item_ids:
                status = await self._get_sync_status(item_id, member_id)
                if status != StripeSyncStatus.deleted:
                    return False
            return True

        async def _revert() -> None:
            for item_id in item_ids:
                status = await self._get_sync_status(item_id, member_id)
                if status != StripeSyncStatus.deleted:
                    await self._uncancel(item_id, member_id)

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
        """Preview cancelling ONE OR MORE of a member's recurring memberships.

        Groups the items by payer and returns one entry per payer that funds any
        of them — each ``affected`` (membership-level), carrying their
        subscription recurring current → new. A single cancel is a one-element
        list → a one-entry affected result. Already-cancelled items are skipped.
        Read-only (staged then restored).

        Raises:
            ValueError: If a membership is not found / non-recurring.
        """
        by_payer: dict[UUID, list[UUID]] = {}
        for item_id in item_ids:
            row = await self._get_membership(item_id, member_id)
            if row["cancel_date"] is not None:
                continue
            self._validate_cancel(row, item_id, member_id)
            by_payer.setdefault(
                UUID(str(row["paid_by_member_id"])), []
            ).append(item_id)
        return [
            await self.preview_payer_change(payer_items, member_id, payer)
            for payer, payer_items in by_payer.items()
        ]

    async def preview_payer_change(
        self,
        item_ids: list[UUID],
        member_id: UUID,
        payer_member_id: UUID,
    ) -> PayerInvoiceChange:
        """One payer's preview entry. ``affected`` is **membership-level** — True
        iff [item_ids] is non-empty (this payer funds ≥1 membership being
        cancelled), decided independently of cost. When affected, stage those
        lines and preview the payer's recurring current → new; when not, nothing
        is cancelled for them (``preview`` None). ALWAYS returns an entry, so a
        caller can show "no change" for an unaffected payer — e.g. removing an
        authorization that funds nothing.
        """
        affected = len(item_ids) > 0
        preview = (
            await self._staged_cancel_preview(
                [(item_id, member_id) for item_id in item_ids],
                payer_member_id,
            )
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

    # ── Private ────────────────────────────────────────────────

    async def _payer_names(
        self,
        payer_member_ids: list[UUID],
    ) -> dict[UUID, tuple[str, str]]:
        """(first_name, last_name) for each payer id — labels the per-payer
        preview entries."""
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
        """Stage every (item_id, member_id) in [items] ``preview_remove``, preview
        ``payer_member_id``'s subscription with those lines dropped, then restore
        ``applied``. The staged-cancel-preview for ONE payer; ``preview_cancel``
        calls it once per payer it groups the items into.

        The preview build drops ``preview_remove`` rows (preview=True excludes
        them) while the real path never bills them; the window is bounded by
        ``finally`` and the per-payer lock (#25) closes the race vs a concurrent
        real sync. Self-heals stale preview rows for the payer before staging.
        """
        # Self-heal: restore any stale preview_remove/preview_add rows for this
        # payer left by a prior crashed preview, before staging our own.
        await self._sweep_stale_preview_rows(payer_member_id)

        async def _stage() -> None:
            for item_id, member_id in items:
                await self._set_sync_status(
                    item_id, member_id, StripeSyncStatus.preview_remove
                )

        async def _cleanup() -> None:
            for item_id, member_id in items:
                await self._set_sync_status(
                    item_id, member_id, StripeSyncStatus.applied
                )

        return await staged_preview(
            stage_fn=_stage,
            cleanup_fn=_cleanup,
            preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                payer_member_id,
                proration_behavior=ProrationBehavior.no_charge,
            ),
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
