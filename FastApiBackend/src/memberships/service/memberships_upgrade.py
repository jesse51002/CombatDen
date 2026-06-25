"""The membership upgrade operation — cross-plan, charge the prorated difference.

An *upgrade* moves a member from their current plan to a DIFFERENT plan's active
price (e.g. Basic -> Premium) and charges the **prorated difference now**. It is
the cross-plan sibling of ``reprice`` (same-plan, a newer price version): both
cancel the old row + insert a successor + converge, sharing the
``MemberMembershipsTransitionBase`` machinery. The difference here: the successor
lands on a *different* plan, the validation guards the recurring window, and the
converge runs with proration so Stripe nets the (new - old) prorated difference.

Mechanism — NO coupon trick. The convergent sync removes the old plan's line and
adds the new plan's line in ONE Stripe ``Subscription.update`` with
``always_invoice`` proration, so Stripe credits the old line's unused time and
charges the new line's prorated time, netting to the prorated difference on one
invoice. This is independent of ``plan_id`` (Stripe sees only prices); the only
constraint is that both prices share the recurring interval — enforced by the
window guard below.

Downgrade guard: a cheaper (or equal) target charges/credits nothing — the op
forces ``no_charge`` so a downgrade simply switches the plan and bills the new
price next cycle.

Standalone (like reprice): it takes its own payer family lock and handles its own
failure with the ``sync_or_revert`` contract. There is no batch upgrade, so this
module imports nothing from ``src.tasks``.
"""

from uuid import UUID

from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from schema.task import ProrationBehavior
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.service.memberships_transition_base import (
    MemberMembershipsTransitionBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
)
from src.shared.db_first_helpers import staged_preview, sync_or_revert
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql


class MemberMembershipsUpgrade(MemberMembershipsTransitionBase):
    """Upgrade a membership to a DIFFERENT plan, charging the prorated diff."""

    async def upgrade(
        self,
        member_id: UUID,
        old_item_id: UUID,
        target_plan_id: UUID,
        proration_behavior: ProrationBehavior,
        idempotency_key: UUID,
    ) -> UUID:
        """Upgrade ONE membership to ``target_plan_id``'s active price.

        DB-first, synchronous, under the payer's family lock. Cancels the old
        row effective today, inserts a successor on the **target** plan at its
        active price, carries the live applied discounts, then the EXISTING
        payment sync converges Stripe with the effective proration (see the
        downgrade guard) and the writeback stamps the successor ``applied`` and
        the old row ``deleted``. Returns the successor's item_id.

        Raises:
            LockBusyError: The payer is busy.
            ValueError: The membership does not validate (not found,
                non-recurring, cancelled, ended), the target is the same plan
                (use reprice), the target plan is deleted / non-recurring /
                a different recurring window, the member already has a recurring
                membership on the target plan, or the target has no active
                price.
            SyncNotConfirmedError: The converge could not be confirmed on
                Stripe — the DB phase has been reverted, the membership is
                exactly as it was.
        """
        payer_id = await self._resolve_payer(old_item_id, member_id)
        async with self._paying_lock.lock([payer_id]):
            row = await self._get_membership(old_item_id, member_id)
            target_plan = await self._get_plan_recurring(
                row["gym_id"],
                target_plan_id,
            )
            self._validate_upgrade(
                row,
                old_item_id,
                member_id,
                target_plan_id,
                target_plan,
            )
            # The member keeps exactly one recurring membership per plan, so
            # they must not already hold an active/frozen recurring on the
            # TARGET plan (the old row is on a different plan, so it is unseen).
            await self._check_no_existing(
                member_id,
                UUID(str(row["gym_id"])),
                [target_plan_id],
            )
            target_price = await self._get_active_price_for_plan(
                row["gym_id"],
                target_plan_id,
            )
            target_price_id = UUID(str(target_price["price_id"]))

            effective = self._effective_proration(
                proration_behavior,
                row["price"],
                target_price["price"],
            )

            # Prorating op: converge the payer to a clean baseline first.
            await self._pre_sync_payments(payer_id)

            # Carry ALL applied discounts onto the successor (via
            # _write_db_phase -> _copy_applied_discounts).
            # KNOWN LIMITATION: copying the OLD plan's linked/family discount
            # onto the NEW plan is logically incorrect — the new plan has its
            # own family-tier config — but it is kept for v1 consistency so
            # staff aren't surprised: the member's bill stays as close as
            # possible to what it was. A later iteration should re-derive the
            # new plan's linked discount instead of copying the old one.
            new_item_id = await self._write_db_phase(
                row,
                member_id,
                old_item_id,
                target_plan_id,
                target_price_id,
                target_price,
            )

            await sync_or_revert(
                sync_fn=lambda: self._payment_sync.update_payments_recurring(
                    payer_id,
                    idempotency_key=idempotency_key,
                    proration_behavior=effective,
                ),
                revert_fn=lambda: self._revert_db_phase(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
                entity_name="member_membership_upgrade",
                crm_pk=str(old_item_id),
                verify_fn=lambda: self._verify(
                    member_id,
                    old_item_id,
                    new_item_id,
                ),
            )
            return new_item_id

    async def upgrade_preview(
        self,
        member_id: UUID,
        old_item_id: UUID,
        target_plan_id: UUID,
        proration_behavior: ProrationBehavior,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what upgrading to ``target_plan_id`` would charge now.

        Runs the SAME validation as ``upgrade`` (so an invalid upgrade raises
        before any staging), then stages the hypothetical post-upgrade state —
        the old row hidden (``preview_remove``) and a ``preview_add`` successor
        on the target plan carrying the copied discounts — runs the read-only
        recurring preview, and ALWAYS reverts the staged rows. Returns the
        ``due_now`` (the prorated difference; ``None`` on a downgrade/equal,
        where nothing is charged now) + ``recurring`` (the new per-cycle bill)
        split, or ``None`` when there is no upcoming invoice to preview.

        Raises:
            Same conditions as ``upgrade`` (the validation is identical).
        """
        payer_id = await self._resolve_payer(old_item_id, member_id)
        async with self._paying_lock.lock([payer_id]):
            row = await self._get_membership(old_item_id, member_id)
            target_plan = await self._get_plan_recurring(
                row["gym_id"],
                target_plan_id,
            )
            self._validate_upgrade(
                row,
                old_item_id,
                member_id,
                target_plan_id,
                target_plan,
            )
            await self._check_no_existing(
                member_id,
                UUID(str(row["gym_id"])),
                [target_plan_id],
            )
            target_price = await self._get_active_price_for_plan(
                row["gym_id"],
                target_plan_id,
            )
            target_price_id = UUID(str(target_price["price_id"]))
            effective = self._effective_proration(
                proration_behavior,
                row["price"],
                target_price["price"],
            )

            # Self-heal any leaked preview rows for this payer before staging.
            await self._sweep_stale_preview_rows(payer_id)

            split = await staged_preview(
                stage_fn=lambda: self._stage_upgrade_preview(
                    row,
                    member_id,
                    old_item_id,
                    target_plan_id,
                    target_price_id,
                    target_price,
                ),
                cleanup_fn=lambda: self._sweep_stale_preview_rows(payer_id),
                preview_fn=lambda: (
                    self._payment_sync.preview_update_payments_recurring(
                        payer_id,
                        proration_behavior=effective,
                    )
                ),
            )
            if split is None:
                return None
            # On a downgrade/equal the engine reuses the steady-state recurring
            # as due_now ("same thing twice"); nothing is actually charged now,
            # so suppress it — mirrors the start preview's no_charge handling.
            prorating = effective == ProrationBehavior.prorate_to_anchor
            return DueNowVsRecurringPreview(
                due_now=split.due_now if prorating else None,
                recurring=split.recurring,
            )

    # ── Private — proration decision ───────────────────────────

    @staticmethod
    def _effective_proration(
        requested: ProrationBehavior,
        old_price: int,
        new_price: int,
    ) -> ProrationBehavior:
        """Charge the prorated difference only on a true upgrade.

        Stripe's native proration would CREDIT the member on a downgrade
        (cheaper target). We never want that here — a downgrade or equal-price
        change just switches the plan and bills the new price next cycle. So
        prorate only when the caller asked for it AND the new price is strictly
        higher; otherwise force ``no_charge``.
        """
        if (
            requested == ProrationBehavior.prorate_to_anchor
            and new_price > old_price
        ):
            return ProrationBehavior.prorate_to_anchor
        return ProrationBehavior.no_charge

    # ── Private — validation / resolution ──────────────────────

    def _validate_upgrade(
        self,
        row: dict,
        old_item_id: UUID,
        member_id: UUID,
        target_plan_id: UUID,
        target_plan: dict,
    ) -> None:
        """Validate the cross-plan upgrade (raises ValueError on any failure)."""
        if row["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Can only upgrade a recurring membership: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        # A set cancel_date (whether already effective OR a future, still-
        # active scheduled cancellation) blocks the upgrade — upgrading would
        # create a fresh successor with no cancel_date, silently dropping the
        # pending cancellation. Staff clear the cancellation first.
        if row["cancel_date"] is not None:
            raise ValueError(
                f"Cannot upgrade a membership with a pending cancellation "
                f"— clear the cancellation first: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        if (
            row["end_date"] is not None
            and row["end_date"] <= gym_today(row["timezone"])
        ):
            raise ValueError(
                f"Cannot upgrade ended membership: "
                f"item_id={old_item_id}, member_id={member_id}"
            )
        if UUID(str(row["plan_id"])) == target_plan_id:
            raise ValueError(
                f"Target is the same plan — use reprice, not upgrade: "
                f"plan_id={target_plan_id}"
            )
        if target_plan["is_deleted"]:
            raise ValueError(
                f"Cannot upgrade to a deleted plan: plan_id={target_plan_id}"
            )
        if target_plan["plan_type"] != PlanType.recurring:
            raise ValueError(
                f"Can only upgrade to a recurring plan: "
                f"plan_id={target_plan_id}"
            )
        if (
            target_plan["duration_unit"],
            target_plan["duration_amount"],
        ) != (row["duration_unit"], row["duration_amount"]):
            raise ValueError(
                "Cannot upgrade across recurring windows "
                f"({row['duration_amount']} {row['duration_unit']} -> "
                f"{target_plan['duration_amount']} "
                f"{target_plan['duration_unit']}): the prorated difference is "
                "only well-defined when both plans bill on the same interval"
            )

    async def _get_plan_recurring(
        self,
        gym_id: UUID,
        plan_id: UUID,
    ) -> dict:
        """The target plan's recurring window (+ ``is_deleted``) for the guard.

        Raises:
            ValueError: If the plan does not exist for the gym.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_plan_recurring.sql")
        params = {"gym_id": str(gym_id), "plan_id": str(plan_id)}
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()
        if not row:
            raise ValueError(
                f"Plan not found: plan_id={plan_id}, gym_id={gym_id}"
            )
        return dict(row)

    async def _stage_upgrade_preview(
        self,
        row: dict,
        member_id: UUID,
        old_item_id: UUID,
        target_plan_id: UUID,
        target_price_id: UUID,
        target_price: dict,
    ) -> None:
        """Stage the hypothetical post-upgrade state for the preview build.

        Hide the old row (``preview_remove`` → dropped by the preview read) and
        insert a ``preview_add`` successor on the TARGET plan with the copied
        discounts (→ kept by the preview read). Always undone by the caller's
        ``_sweep_stale_preview_rows`` cleanup. No ``cancel_date`` is set (unlike
        the real op) — the status flip alone hides the old row from the preview.
        """
        today = gym_today(row["timezone"])
        await self._set_sync_status(
            old_item_id,
            member_id,
            StripeSyncStatus.preview_remove,
        )
        async with self._db_pool.session() as session:
            new_item_id = await self._insert_successor(
                session,
                row,
                member_id,
                target_plan_id,
                target_price_id,
                target_price,
                today,
                sync_status=StripeSyncStatus.preview_add,
            )
            await self._copy_applied_discounts(
                session,
                old_item_id,
                new_item_id,
                today,
                sync_status=StripeSyncStatus.preview_add,
            )
            await session.commit()
