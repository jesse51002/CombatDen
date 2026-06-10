"""Start (create) a new membership: DB first, then Stripe, then set stripe ID."""

from __future__ import annotations

import logging
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.discounts.schema.discounts_schema import (
    DiscountValue,
)
from src.member_memberships import SQL_DIR
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.schema.payments_invoice_schema import (
    DueNowVsRecurringPreview,
    PreviewInvoice,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentPreviewRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import (
    staged_preview,
    sync_or_revert,
)
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.discounts.service.discounts.discounts_service import (
        DiscountsService,
    )
    from src.member_memberships.service.memberships.member_memberships_update_discounts import (  # noqa: E501
        MemberMembershipsUpdateDiscounts,
    )
    from src.member_memberships.service.payment_sync.payment_sync_one_time import (
        PaymentSyncOneTime,
    )
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )
    from src.shared.billing_parent_resolver import BillingParentResolver

logger = logging.getLogger(__name__)


class MemberMembershipsStart(MemberMembershipsBase):
    """Create a new membership using the DB-first pattern."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
        parent_resolver: BillingParentResolver,
        payment_sync_one_time: PaymentSyncOneTime,
        update_discounts: MemberMembershipsUpdateDiscounts,
        discounts_service: DiscountsService,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service
        self._parent_resolver = parent_resolver
        self._payment_sync_one_time = payment_sync_one_time
        self._update_discounts = update_discounts
        self._discounts = discounts_service

    async def start(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        idempotency_key: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
        discount_ids: list[UUID] | None = None,
        custom_discounts: list[DiscountValue] | None = None,
    ) -> None:
        """Start a new membership for a member.

        Validates the plan/price, checks no duplicate active
        membership exists, ensures the account is not frozen,
        inserts the CRM row, syncs to Stripe, then sets the
        stripe_item_id on the CRM row. Memberships always begin
        on the day this method is called — future start dates
        are not supported. Optional ``discount_ids`` / ``custom_discounts`` are
        snapshotted before the first charge, so it is discounted at creation.

        Args:
            member_id: The member.
            gym_id: The gym.
            plan_id: The membership plan.
            price_id: The price tier.
            prorate: Whether to prorate the first charge.
            paid_with_cash: If True, the first invoice is marked
                paid out of band in Stripe instead of charging the
                customer's default payment method. Cash is a
                backup — future billing cycles still auto-charge
                the card as normal.

        Raises:
            ValueError: If plan/price invalid, membership already
                exists, or account is frozen.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        plan_price = await self._get_plan_price(gym_id, plan_id, price_id)
        await self._check_no_existing(member_id, gym_id, plan_id)

        parent = await self._parent_resolver.resolve_parent(member_id)
        if parent.is_frozen:
            raise ValueError("Cannot start membership: account is frozen")

        start_date = gym_today(parent.timezone)
        plan_type = PlanType(plan_price["plan_type"])
        is_recurring = plan_type == PlanType.recurring

        # ── Calculate dates ────────────────────────────────────
        end_date: date | None = None
        if not is_recurring and plan_price["duration_amount"] and plan_price["duration_unit"]:
            end_date = self._calculate_end_date(
                start_date,
                plan_price["duration_amount"],
                plan_price["duration_unit"],
            )

        if not plan_price["stripe_price_id"]:
            raise ValueError(f"Plan price {plan_price['price_id']} missing stripe_price_id")

        # Pre-sync (recurring): converge the family to a clean DB↔Stripe baseline
        # before inserting the new membership. (One-time has no subscription to
        # converge.)
        if is_recurring:
            await self._pre_sync_payments(member_id)

        # ── Step 1: DB insert (NULL stripe_item_id) ───────────
        item_id = await self._crm_insert(
            member_id=member_id,
            gym_id=gym_id,
            plan_id=plan_id,
            price_id=price_id,
            start_date=start_date,
            end_date=end_date,
            last_paid_date=start_date,
            next_due_date=None,
            stripe_item_id=None,
            prorate=prorate,
            total_price=plan_price["price"],
        )

        # ── Discounts at creation (both paths) ────────────────
        # Mint any inline customs, then snapshot all presets (preset + minted)
        # BEFORE the engine call, so the first (one-time: only) invoice is
        # discounted. The revert undoes snapshots + minted customs + the pending
        # row together if the charge/sync then fails.
        minted_ids = await self._discounts.mint_custom_discounts(
            gym_id, custom_discounts or []
        )
        all_discount_ids = [*(discount_ids or []), *minted_ids]
        applied_ids: list[UUID] = []
        if all_discount_ids:
            applied_ids = await self._update_discounts.add_preset_snapshots(
                item_id=item_id,
                member_id=member_id,
                gym_id=gym_id,
                discount_ids=all_discount_ids,
                apply_date=start_date,
            )

        async def _revert() -> None:
            if applied_ids:
                await self._update_discounts.delete_snapshots(
                    member_id, applied_ids
                )
            for discount_id in minted_ids:
                await self._discounts.delete_discount(discount_id)
            await self._delete_pending(str(item_id))

        # ── Step 2: charge / sync ─────────────────────────────
        # Both paths are DB-first + verified: the pending row inserted above is
        # visible to the engine, which pushes it to Stripe and writes its ids /
        # 'applied' status back itself (recurring → the subscription sync;
        # one-time → the consolidated invoice charge). Nothing to stamp here.
        if is_recurring:
            # Recurring is DB-first + verified: the sync adds the pending row to
            # Stripe and writes its line id / next_due_date / 'applied' status
            # back. If the sync fails or the row is not stamped 'applied', the
            # pending row is deleted so the DB stays in sync with Stripe.
            async def _sync_recurring() -> None:
                await self._payment_sync.update_payments_recurring(
                    member_id,
                    idempotency_key=idempotency_key,
                    pay_first_invoice_out_of_band=paid_with_cash,
                    proration_behavior=(
                        "always_invoice" if prorate else "none"
                    ),
                )

            async def _verify_added() -> bool:
                status = await self._get_sync_status(item_id, member_id)
                return status == StripeSyncStatus.applied

            await sync_or_revert(
                sync_fn=_sync_recurring,
                revert_fn=_revert,
                entity_name="member_membership",
                crm_pk=str(item_id),
                verify_fn=_verify_added,
            )
        else:
            # One-time is DB-first + verified, like recurring: the pending row is
            # visible to the one-time charge, which cuts a single invoice and
            # writes its line id + stripe_one_time_invoice_id + total_price +
            # 'applied' back itself. If the charge fails or the row is not stamped
            # 'applied', the pending row is deleted so the DB stays in sync.
            async def _run_charge() -> None:
                await self._payment_sync_one_time.charge_one_time(
                    member_id,
                    idempotency_key=idempotency_key,
                    paid_with_cash=paid_with_cash,
                )

            async def _verify_charged() -> bool:
                status = await self._get_sync_status(item_id, member_id)
                return status == StripeSyncStatus.applied

            await sync_or_revert(
                sync_fn=_run_charge,
                revert_fn=_revert,
                entity_name="member_membership",
                crm_pk=str(item_id),
                verify_fn=_verify_charged,
            )

    async def preview(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> DueNowVsRecurringPreview | None:
        """Preview what starting a membership would charge.

        Runs every validation ``start`` runs (plan/price lookup,
        duplicate check, frozen-account check) and then calls the
        corresponding Stripe invoice preview instead of creating
        rows or subscriptions.

        Args:
            Identical to ``start``. ``paid_with_cash`` is accepted
            for signature parity but has no effect — preview
            performs no charge.

        Returns:
            A due-now / recurring split, or ``None`` for a recurring
            plan whose resulting bucket produces no upcoming invoice.
            A one-time plan returns the whole charge in ``due_now``
            with an empty ``recurring``.

        Raises:
            ValueError: Same conditions as ``start``.
        """
        plan_price = await self._get_plan_price(gym_id, plan_id, price_id)
        await self._check_no_existing(member_id, gym_id, plan_id)

        parent = await self._parent_resolver.resolve_parent(member_id)
        if parent.is_frozen:
            raise ValueError("Cannot start membership: account is frozen")

        if not plan_price["stripe_price_id"]:
            raise ValueError(f"Plan price {plan_price['price_id']} missing stripe_price_id")

        plan_type = PlanType(plan_price["plan_type"])
        is_recurring = plan_type == PlanType.recurring

        if is_recurring:
            # Stage a 'preview_add' membership row so the preview reflects the new
            # membership, then delete it (finally). The real path excludes
            # preview_add (can never bill it); the preview build (preview=True)
            # includes it. Race vs a concurrent real sync is bounded by the
            # cleanup; the per-parent lock (#25) closes it (TODO).
            start_date = gym_today(parent.timezone)
            staged: list[UUID] = []

            async def _stage() -> None:
                item_id = await self._crm_insert(
                    member_id=member_id,
                    gym_id=gym_id,
                    plan_id=plan_id,
                    price_id=price_id,
                    start_date=start_date,
                    end_date=None,
                    last_paid_date=start_date,
                    next_due_date=None,
                    stripe_item_id=None,
                    prorate=prorate,
                    total_price=plan_price["price"],
                    sync_status=StripeSyncStatus.preview_add,
                )
                staged.append(item_id)

            async def _cleanup() -> None:
                if staged:
                    await self._delete_pending(str(staged[0]))

            return await staged_preview(
                stage_fn=_stage,
                cleanup_fn=_cleanup,
                preview_fn=lambda: self._payment_sync.preview_update_payments_recurring(
                    member_id,
                    proration_behavior=(
                        "always_invoice" if prorate else "none"
                    ),
                ),
            )

        # A one-time purchase is charged entirely now; nothing recurs.
        one_time = await self._preview_one_time(
            stripe_customer_id=parent.stripe_customer_id,
            stripe_price_id=plan_price["stripe_price_id"],
            gym_id=parent.gym_id,
        )
        return DueNowVsRecurringPreview(due_now=one_time, recurring=None)

    # ── Private ────────────────────────────────────────────────

    async def _get_plan_price(
        self,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
    ) -> dict:
        """Validate plan+price exist and are usable.

        Raises:
            ValueError: If not found, plan deleted, or price inactive.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_plan_price.sql")
        params = {
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
            "price_id": str(price_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Plan/price not found: plan_id={plan_id}, price_id={price_id}, gym_id={gym_id}"
            )
        if row["plan_is_deleted"]:
            raise ValueError(f"Plan is deleted: plan_id={plan_id}")
        if not row["price_is_active"]:
            raise ValueError(f"Price is not active: price_id={price_id}")
        return dict(row)

    async def _check_no_existing(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
    ) -> None:
        """Ensure no active/frozen membership exists for this plan.

        Raises:
            ValueError: If an active or frozen membership already exists.
        """
        sql = load_sql(SQL_DIR / "member_memberships_check_existing.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            exists = result.fetchone()

        if exists:
            raise ValueError(
                f"Active membership already exists: "
                f"member_id={member_id}, gym_id={gym_id}, "
                f"plan_id={plan_id}"
            )

    async def _crm_insert(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        start_date: date,
        end_date: date | None,
        last_paid_date: date | None,
        next_due_date: date | None,
        stripe_item_id: str | None,
        prorate: bool,
        total_price: int,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
    ) -> UUID:
        """Insert a new membership row. Returns the generated item_id.

        ``sync_status`` defaults to ``not_added`` (the real start's pending row);
        the start preview inserts ``preview_add`` so the dry-run sees it but the
        real path never bills it. Memberships are created discount-free —
        discounts are applied afterward via the apply path.
        """
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
            "price_id": str(price_id),
            "start_date": start_date,
            "end_date": end_date,
            "last_paid_date": last_paid_date,
            "next_due_date": next_due_date,
            "stripe_item_id": stripe_item_id,
            "prorate": prorate,
            "total_price": total_price,
            "sync_status": sync_status.value,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().one()
            await session.commit()
        return row["item_id"]

    async def _delete_pending(self, item_id: str) -> None:
        """Hard-delete a pending membership row (NULL stripe_item_id)."""
        sql = load_sql(SQL_DIR / "member_memberships_delete_pending.sql")
        async with self._db_pool.session() as session:
            await session.execute(text(sql), {"item_id": item_id})
            await session.commit()

    async def _preview_one_time(
        self,
        stripe_customer_id: str,
        stripe_price_id: str,
        gym_id: UUID,
    ) -> PreviewInvoice:
        """Preview the invoice for a non-recurring plan."""
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(gym_id)
        request = PaymentsInvoicePaymentPreviewRequest(
            stripe_customer_id=stripe_customer_id,
            items=[PaymentsInvoiceItemSpec(stripe_price_id=stripe_price_id)],
        )
        return await self._payment_service.preview_invoice_payment(
            request,
            stripe_account_id,
        )

    @staticmethod
    def _calculate_end_date(
        start: date,
        duration_amount: int,
        duration_unit: str,
    ) -> date:
        """Calculate membership end date from plan duration."""
        if duration_unit == "week":
            return start + relativedelta(weeks=duration_amount)
        if duration_unit == "month":
            return start + relativedelta(months=duration_amount)
        if duration_unit == "year":
            return start + relativedelta(years=duration_amount)
        raise ValueError(f"Unknown duration_unit: {duration_unit}")
