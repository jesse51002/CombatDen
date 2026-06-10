"""Apply (add / remove) discount snapshots on an existing membership.

Applying a discount is an explicit add / remove of snapshot rows on
member_membership_applied_discounts — never a replace-set, never an edit. Each
snapshot freezes the membership to one immutable discount value version
(value_id); a later edit to the discount mints a NEW version, so the applied row
stays pinned to the version it was applied at.

- A regular preset newly desired -> INSERT a snapshot referencing the preset's
  ACTIVE value version, with the absolute end_date resolved from that version's
  lifetime spec. A preset already applied to this membership is skipped (left
  frozen). A snapshot in the remove list -> DELETE.
- ``once`` snapshots leave end_date NULL until the sync stamps it on consumption.

Any discount is applied this way by id, including a ``linked`` (family) discount:
the membership/family flow passes the linked discount's id in ``add_preset_ids``
and it freezes a snapshot to that discount's active value like any other.

After writing the snapshot rows the membership's subscription is re-synced so the
sync computes each consolidated line's coupon and writes the resolved
stripe_coupon_id back onto the contributing snapshots. Stripe attach for ``once``
discounts lives entirely in the sync: a just-applied ``once`` snapshot has a NULL
stripe_coupon_id and NULL end_date; the first re-sync treats it as pending,
find-or-creates its deterministic coupon, attaches it, and writes the coupon id
back (the consumption handle). On a later cycle the coupon is absent from the
live subscription, so the sync detects consumption and stamps end_date.
"""

import logging
from datetime import date
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.gym_discount import DiscountDurationUnit, DiscountMode
from schema.member_membership import StripeSyncStatus
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.db_first_helpers import staged_preview
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_APPLIED_SQL = SQL_DIR / "applied_discounts"


class MemberMembershipsUpdateDiscounts(MemberMembershipsBase):
    """Add / remove applied-discount snapshots on a live membership."""

    async def add_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        preset_ids: list[UUID],
        idempotency_key: UUID,
        preview: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Add a snapshot per named preset and re-sync — or preview the add.

        Inserts a snapshot for each newly-desired regular preset (skipping
        presets already applied) referencing the preset's active value version,
        then re-syncs Stripe so the sync resolves and writes back the coupon(s).
        No mid-cycle invoice is cut — the next renewal is the first cycle to bill
        the new total.

        ``preview=True`` stages the adds as ``preview_add`` rows, previews the
        resulting bill, and deletes them — nothing is committed. Returns the
        invoice preview in that mode, else ``None``.

        Raises:
            ValueError: If membership not found, cancelled, ended, missing
                Stripe linkage, or a preset is unknown / archived / cross-gym.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_apply(row, item_id, member_id)
        gym_id = row["gym_id"]
        apply_date = gym_today(row["timezone"])

        if preview:
            staged: list[UUID] = []

            async def _stage() -> None:
                staged.extend(
                    await self.add_preset_snapshots(
                        item_id=item_id,
                        member_id=member_id,
                        gym_id=gym_id,
                        preset_ids=preset_ids,
                        apply_date=apply_date,
                        sync_status=StripeSyncStatus.preview_add,
                    )
                )

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=lambda: self.delete_snapshots(member_id, staged),
                preview_fn=lambda: (
                    self._payment_sync.preview_update_payments_recurring(
                        member_id,
                    )
                ),
            )

        await self.add_preset_snapshots(
            item_id=item_id,
            member_id=member_id,
            gym_id=gym_id,
            preset_ids=preset_ids,
            apply_date=apply_date,
        )
        await self._payment_sync.update_payments_recurring(
            member_id,
            idempotency_key=idempotency_key,
        )
        return None

    async def remove_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        applied_ids: list[UUID],
        idempotency_key: UUID,
        preview: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Remove the named discount snapshots and re-sync — or preview it.

        Deletes the named snapshot rows then re-syncs Stripe so the consolidated
        line drops the removed discount(s). No mid-cycle invoice is cut.

        ``preview=True`` stages the removal by flipping those rows to
        ``preview_remove`` (the preview build drops them), previews the bill,
        then reverts them to ``applied`` — nothing is committed. Returns the
        invoice preview in that mode, else ``None``.

        The staged ``preview_remove`` is safe only because the facade holds the
        per-parent ``PayingMemberLock`` around this op — that serializes the
        paying family, so no concurrent real sync can drop the staged row before
        ``finally`` reverts it to ``applied``.

        Raises:
            ValueError: If membership not found, cancelled, ended, or missing
                Stripe linkage.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_apply(row, item_id, member_id)

        if preview:
            async def _stage() -> None:
                await self._set_snapshots_status(
                    member_id, applied_ids, StripeSyncStatus.preview_remove,
                )

            async def _cleanup() -> None:
                await self._set_snapshots_status(
                    member_id, applied_ids, StripeSyncStatus.applied,
                )

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=_cleanup,
                preview_fn=lambda: (
                    self._payment_sync.preview_update_payments_recurring(
                        member_id,
                    )
                ),
            )

        await self.delete_snapshots(member_id, applied_ids)
        await self._payment_sync.update_payments_recurring(
            member_id,
            idempotency_key=idempotency_key,
        )
        return None

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _validate_apply(
        row: dict,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Validate a membership can have its discounts changed."""
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot apply discounts on cancelled membership: "
                f"item_id={item_id}, member_id={member_id}"
            )
        if row["end_date"] is not None and row["end_date"] <= gym_today(row["timezone"]):
            raise ValueError(
                f"Cannot apply discounts on ended membership: "
                f"item_id={item_id}, member_id={member_id}"
            )
        if not row["stripe_item_id"]:
            raise ValueError(f"Membership missing stripe_item_id for item_id={item_id}")

    async def delete_snapshots(
        self,
        member_id: UUID,
        applied_discount_ids: list[UUID],
    ) -> None:
        """DELETE the named snapshot rows (scoped to the owning member)."""
        if not applied_discount_ids:
            return
        sql = load_sql(_APPLIED_SQL / "delete_applied_discount.sql")
        async with self._db_pool.session() as session:
            for applied_discount_id in applied_discount_ids:
                await session.execute(
                    text(sql),
                    {
                        "applied_discount_id": str(applied_discount_id),
                        "member_id": str(member_id),
                    },
                )
            await session.commit()

    async def _set_snapshots_status(
        self,
        member_id: UUID,
        applied_discount_ids: list[UUID],
        status: StripeSyncStatus,
    ) -> None:
        """Stamp the Stripe-sync status on the named snapshot rows.

        Used by the preview staging: flip the to-be-removed snapshots to
        ``preview_remove`` and back to ``applied`` on cleanup. No-op for an
        empty list.
        """
        if not applied_discount_ids:
            return
        sql = load_sql(_APPLIED_SQL / "set_applied_discount_sync_status.sql")
        async with self._db_pool.session() as session:
            for applied_discount_id in applied_discount_ids:
                await session.execute(
                    text(sql),
                    {
                        "applied_discount_id": str(applied_discount_id),
                        "member_id": str(member_id),
                        "sync_status": status.value,
                    },
                )
            await session.commit()

    async def add_preset_snapshots(
        self,
        item_id: UUID,
        member_id: UUID,
        gym_id: UUID,
        preset_ids: list[UUID],
        apply_date: date,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
    ) -> list[UUID]:
        """INSERT a snapshot per newly-desired regular preset; return their ids.

        A preset already applied to this membership is skipped (left frozen).
        Each new snapshot references the preset's active value version and
        resolves its absolute end_date from that version's lifetime spec.
        ``sync_status`` is ``not_added`` for a real apply (the writeback stamps
        ``applied``) or ``preview_add`` for a dry-run preview.
        """
        if not preset_ids:
            return []

        already_applied = await self._existing_discount_ids(item_id, member_id)
        insert_sql = load_sql(_APPLIED_SQL / "insert_applied_discount.sql")

        inserted: list[UUID] = []
        async with self._db_pool.session() as session:
            for preset_id in preset_ids:
                if preset_id in already_applied:
                    continue
                value = await self._get_active_value(session, preset_id, gym_id)
                end_date = self._resolve_end_date(value, apply_date)
                result = await session.execute(
                    text(insert_sql),
                    {
                        "item_id": str(item_id),
                        "member_id": str(member_id),
                        "gym_id": str(gym_id),
                        "value_id": str(value["value_id"]),
                        "end_date": end_date,
                        "sync_status": sync_status.value,
                    },
                )
                inserted.append(
                    UUID(str(result.mappings().one()["applied_discount_id"]))
                )
            await session.commit()
        return inserted

    async def _existing_discount_ids(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> set[UUID]:
        """Return discount_ids already applied to this membership."""
        sql = load_sql(_APPLIED_SQL / "get_applied_discounts_by_item.sql")
        params = {"item_id": str(item_id), "member_id": str(member_id)}
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = result.mappings().fetchall()
        return {UUID(str(r["discount_id"])) for r in rows}

    @staticmethod
    async def _get_active_value(
        session: AsyncSession,
        preset_id: UUID,
        gym_id: UUID,
    ) -> dict:
        """Read a preset's active value version to freeze onto a snapshot.

        Raises:
            ValueError: If the preset is unknown, archived, or cross-gym.
        """
        sql = load_sql(_APPLIED_SQL / "get_preset_for_apply.sql")
        result = await session.execute(
            text(sql),
            {"discount_id": str(preset_id), "gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
        if not row:
            raise ValueError(
                f"Discount preset not found for gym_id={gym_id}: {preset_id}",
            )
        return dict(row)

    @staticmethod
    def _resolve_end_date(value: dict, apply_date: date) -> date | None:
        """Resolve a snapshot's absolute end_date from the value's lifetime.

        ``once`` -> NULL (stamped by the sync on consumption). ``ongoing`` with a
        duration span -> apply_date + span. ``ongoing`` with an explicit end_date
        -> copied. ``ongoing`` with neither -> NULL (forever).
        """
        if value["discount_mode"] == DiscountMode.once.value:
            return None

        explicit_end = value["end_date"]
        if explicit_end is not None:
            return explicit_end

        amount = value["duration_amount"]
        unit = value["duration_unit"]
        if amount is None or unit is None:
            return None

        if unit == DiscountDurationUnit.day.value:
            return apply_date + relativedelta(days=amount)
        if unit == DiscountDurationUnit.week.value:
            return apply_date + relativedelta(weeks=amount)
        if unit == DiscountDurationUnit.month.value:
            return apply_date + relativedelta(months=amount)
        raise ValueError(f"Unknown discount duration_unit: {unit}")
