"""Apply (add / remove) applied-discount rows on an existing membership.

Applying a discount is an explicit add / remove of applied-discount rows on
member_membership_applied_discounts — never a replace-set, never an edit. Each
applied-discount row freezes the membership to one immutable discount value version
(value_id); a later edit to the discount mints a NEW version, so the applied row
stays pinned to the version it was applied at.

- A regular preset newly desired -> INSERT an applied-discount row referencing the
  preset's ACTIVE value version, with the absolute end_date resolved from that
  version's lifetime spec (a duration span -> apply_date + span; an explicit
  end_date copied verbatim; neither -> NULL = forever). A preset already applied to
  this membership is skipped (left frozen). An applied-discount row in the remove
  list -> DELETE.

A discount is applied this way by id: the membership flow passes the discount's
id in ``discount_ids`` and it freezes an applied-discount row to that discount's
active value version like any other.

After writing the applied-discount rows the membership's subscription is re-synced
so the sync computes each consolidated line's coupon and writes the resolved
stripe_coupon_id back onto the contributing applied-discount rows. The coupon is
find-or-created once per distinct value (a single Stripe ``forever`` coupon); the
discount's expiry is bounded by OUR resolved end_date, never by Stripe — the
applied-discount read simply drops a row once its end_date has passed.

DiscountsService never touches applied-discount rows — it owns only
``gym_discounts`` / ``gym_discount_values``. ``mint_custom_discounts`` returns
plain discount ids that the memberships side applies exactly like presets.
"""

import logging
from datetime import date
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.gym_discount import DiscountDurationUnit, DiscountType
from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.db_first_helpers import staged_preview, sync_or_revert
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_APPLIED_SQL = SQL_DIR / "applied_discounts"


class MemberMembershipsDiscounts(MemberMembershipsBase):
    """Add / remove applied-discount rows on a live membership."""

    async def add_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        discount_ids: list[UUID],
        idempotency_key: UUID,
        preview: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Add an applied-discount row per named preset and re-sync — or preview the add.

        Inserts an applied-discount row for each newly-desired regular preset
        (skipping presets already applied) referencing the preset's active value
        version, then re-syncs Stripe so the sync resolves and writes back the
        coupon(s). No mid-cycle invoice is cut — the next renewal is the first
        cycle to bill the new total.

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
        payer_member_id = row["paid_by_member_id"]
        apply_date = gym_today(row["timezone"])

        if preview:
            # Self-heal: restore any stale preview_remove/preview_add rows for
            # this payer left by a prior crashed preview, before staging ours.
            await self._sweep_stale_preview_rows(payer_member_id)

            staged: list[UUID] = []

            async def _stage() -> None:
                staged.extend(
                    await self.add_applied_discounts(
                        item_id=item_id,
                        member_id=member_id,
                        gym_id=gym_id,
                        discount_ids=discount_ids,
                        apply_date=apply_date,
                        sync_status=StripeSyncStatus.preview_add,
                    )
                )

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=lambda: self.delete_applied_discounts(member_id, staged),
                preview_fn=lambda: (
                    self._payment_sync.preview_update_payments_recurring(
                        payer_member_id,
                    )
                ),
            )

        inserted = await self.add_applied_discounts(
            item_id=item_id,
            member_id=member_id,
            gym_id=gym_id,
            discount_ids=discount_ids,
            apply_date=apply_date,
        )
        # DB-first: the rows are inserted; the sync resolves + stamps them
        # 'applied'. Verify the writeback landed, else revert the inserts so the
        # DB never drifts out of sync with Stripe.
        await sync_or_revert(
            sync_fn=lambda: self._payment_sync.update_payments_recurring(
                payer_member_id,
                idempotency_key=idempotency_key,
            ),
            revert_fn=lambda: self.delete_applied_discounts(
                member_id, inserted,
            ),
            entity_name="member_membership_applied_discounts",
            crm_pk=str(item_id),
            verify_fn=lambda: self._applied_discounts_confirmed(inserted),
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
        """Remove the named applied-discount rows and re-sync — or preview it.

        Deletes the named applied-discount rows then re-syncs Stripe so the
        consolidated line drops the removed discount(s). No mid-cycle invoice is cut.

        ``preview=True`` stages the removal by flipping those rows to
        ``preview_remove`` (the preview build drops them), previews the bill,
        then reverts them to ``applied`` — nothing is committed. Returns the
        invoice preview in that mode, else ``None``.

        The staged ``preview_remove`` is safe only because the facade holds the
        per-payer ``PayingMemberLock`` around this op — that serializes the
        paying family, so no concurrent real sync can drop the staged row before
        ``finally`` reverts it to ``applied``.

        Raises:
            ValueError: If membership not found, cancelled, ended, or missing
                Stripe linkage.
        """
        row = await self._get_membership(item_id, member_id)
        self._validate_apply(row, item_id, member_id)
        payer_member_id = row["paid_by_member_id"]

        if preview:
            # Self-heal: restore any stale preview_remove/preview_add rows for
            # this payer left by a prior crashed preview, before staging ours.
            await self._sweep_stale_preview_rows(payer_member_id)

            async def _stage() -> None:
                await self._set_applied_discounts_status(
                    member_id, applied_ids, StripeSyncStatus.preview_remove,
                )

            async def _cleanup() -> None:
                await self._set_applied_discounts_status(
                    member_id, applied_ids, StripeSyncStatus.applied,
                )

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=_cleanup,
                preview_fn=lambda: (
                    self._payment_sync.preview_update_payments_recurring(
                        payer_member_id,
                    )
                ),
            )

        # Snapshot the rows BEFORE deleting so a failed sync can restore them.
        # A hard-deleted row has no status to verify (the removal's effect on
        # Stripe is execute_sync's, which still raises on failure) — so this is
        # revert-on-exception only, no verify_fn.
        snapshot = await self._read_applied_discounts_by_ids(applied_ids)
        await self.delete_applied_discounts(member_id, applied_ids)
        await sync_or_revert(
            sync_fn=lambda: self._payment_sync.update_payments_recurring(
                payer_member_id,
                idempotency_key=idempotency_key,
            ),
            revert_fn=lambda: self._restore_applied_discounts(snapshot),
            entity_name="member_membership_applied_discounts",
            crm_pk=str(item_id),
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
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Membership {item_id} is non-recurring: its single invoice is "
                f"already charged, so discounts can only be applied at creation"
            )
        if not row["stripe_item_id"]:
            raise ValueError(f"Membership missing stripe_item_id for item_id={item_id}")

    async def delete_applied_discounts(
        self,
        member_id: UUID,
        applied_discount_ids: list[UUID],
    ) -> None:
        """DELETE the named applied-discount rows (scoped to the owning member)."""
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

    async def _set_applied_discounts_status(
        self,
        member_id: UUID,
        applied_discount_ids: list[UUID],
        status: StripeSyncStatus,
    ) -> None:
        """Stamp the Stripe-sync status on the named applied-discount rows.

        Used by the preview staging: flip the to-be-removed applied-discount rows
        to ``preview_remove`` and back to ``applied`` on cleanup. No-op for an
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

    async def _read_applied_discounts_by_ids(
        self,
        applied_discount_ids: list[UUID],
    ) -> list[dict]:
        """Read the unfiltered applied-discount rows for the given ids.

        Reads the unfiltered base (service-role) so half-synced rows are visible.
        Backs the add-verify (each row's sync status) and the remove-revert
        snapshot (the fields needed to re-insert). Empty in -> empty out.
        """
        if not applied_discount_ids:
            return []
        sql = load_sql(_APPLIED_SQL / "get_applied_discounts_by_ids.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "applied_discount_ids": [
                        str(i) for i in applied_discount_ids
                    ],
                },
            )
            return [dict(r) for r in result.mappings().fetchall()]

    async def _applied_discounts_confirmed(
        self,
        applied_discount_ids: list[UUID],
    ) -> bool:
        """True iff every given applied-discount row was stamped ``applied``.

        The add writeback (``set_applied_discount_coupon_id``) flips each
        contributing row ``not_added`` -> ``applied``; an unconfirmed sync leaves
        it un-stamped. An empty list is trivially confirmed (nothing to stamp).
        """
        if not applied_discount_ids:
            return True
        rows = await self._read_applied_discounts_by_ids(applied_discount_ids)
        statuses = {
            UUID(str(r["applied_discount_id"])): r["stripe_sync_status"]
            for r in rows
        }
        return all(
            statuses.get(aid) == StripeSyncStatus.applied.value
            for aid in applied_discount_ids
        )

    async def _restore_applied_discounts(
        self,
        snapshot: list[dict],
    ) -> None:
        """Re-insert applied-discount rows from a pre-delete snapshot.

        Reverts a remove whose sync did not land: re-inserts each removed row at
        its original value version + end_date + status (new ids are fine — the
        discount effect is restored and the next sync re-resolves its coupon).
        """
        if not snapshot:
            return
        insert_sql = load_sql(_APPLIED_SQL / "insert_applied_discount.sql")
        async with self._db_pool.session() as session:
            for row in snapshot:
                await session.execute(
                    text(insert_sql),
                    {
                        "item_id": str(row["item_id"]),
                        "member_id": str(row["member_id"]),
                        "gym_id": str(row["gym_id"]),
                        "value_id": str(row["value_id"]),
                        "end_date": row["end_date"],
                        "sync_status": str(row["stripe_sync_status"]),
                    },
                )
            await session.commit()

    async def add_applied_discounts(
        self,
        item_id: UUID,
        member_id: UUID,
        gym_id: UUID,
        discount_ids: list[UUID],
        apply_date: date,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
        allow_custom: bool = False,
    ) -> list[UUID]:
        """INSERT an applied-discount row per newly-desired discount; return their ids.

        A discount already applied to this membership is skipped (left frozen).
        Each new applied-discount row references the discount's active value version
        and resolves its absolute end_date from that version's lifetime spec.
        ``sync_status`` is ``not_added`` for a real apply (the writeback stamps
        ``applied``) or ``preview_add`` for a dry-run preview.

        ``custom`` discounts are one-shot and single-owner (DB-enforced): only
        the membership flow that just minted them applies them, by passing
        ``allow_custom=True``. The default rejects a custom id, so the public
        add path can never attach a minted custom to another membership.
        """
        if not discount_ids:
            return []

        already_applied = await self._existing_discount_ids(item_id, member_id)
        insert_sql = load_sql(_APPLIED_SQL / "insert_applied_discount.sql")

        inserted: list[UUID] = []
        async with self._db_pool.session() as session:
            for discount_id in discount_ids:
                if discount_id in already_applied:
                    continue
                value = await self._get_active_value(session, discount_id, gym_id)
                if (
                    not allow_custom
                    and value["discount_type"] == DiscountType.custom.value
                ):
                    raise ValueError(
                        f"Custom discount {discount_id} is single-use and can "
                        f"only be applied by the membership flow that minted it"
                    )
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
        discount_id: UUID,
        gym_id: UUID,
    ) -> dict:
        """Read a discount's active value version to freeze onto an applied-discount row.

        Raises:
            ValueError: If the discount is unknown, archived, or cross-gym.
        """
        sql = load_sql(_APPLIED_SQL / "get_preset_for_apply.sql")
        result = await session.execute(
            text(sql),
            {"discount_id": str(discount_id), "gym_id": str(gym_id)},
        )
        row = result.mappings().fetchone()
        if not row:
            raise ValueError(
                f"Discount not found for gym_id={gym_id}: {discount_id}",
            )
        return dict(row)

    @staticmethod
    def _resolve_end_date(value: dict, apply_date: date) -> date | None:
        """Resolve an applied-discount row's absolute end_date from the value's lifetime.

        A duration span (duration_amount + duration_unit) -> apply_date + span; an
        explicit end_date -> copied; neither -> NULL (forever). The Stripe coupon
        is always ``forever`` — this resolved end_date is the cutoff the sync read
        enforces (it drops the discount on/after it), so a 1-``cycle`` span is the
        single-invoice discount that replaced the old ``once`` mode.

        A ``cycle`` is one plan billing cycle. Recurring plans are monthly
        (DB-enforced ``recurring_must_be_monthly``), so one cycle = one month;
        if recurring plans ever gain other intervals this must resolve a cycle
        against the membership's plan billing period.
        """
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
        if unit in (
            DiscountDurationUnit.month.value,
            DiscountDurationUnit.cycle.value,
        ):
            return apply_date + relativedelta(months=amount)
        raise ValueError(f"Unknown discount duration_unit: {unit}")
