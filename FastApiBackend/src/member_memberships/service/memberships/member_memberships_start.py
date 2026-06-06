"""Start (create) a new membership: DB first, then Stripe, then set stripe ID."""

from __future__ import annotations

import logging
from datetime import date
from typing import TYPE_CHECKING
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import SyncItem
from src.member_memberships.service.memberships.member_memberships_base import (
    MemberMembershipsBase,
)
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentPreviewRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import cleanup_pending_row
from src.shared.gym_stripe_service import GymStripeService
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.payments.service.payments_stripe_payment_service import (
        PaymentsStripePaymentService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsStart(MemberMembershipsBase):
    """Create a new membership using the DB-first pattern."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payment_service: PaymentsStripePaymentService,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payment_service = payment_service

    async def start(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        idempotency_key: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> None:
        """Start a new membership for a member.

        Validates the plan/price, checks no duplicate active
        membership exists, ensures the account is not frozen,
        inserts the CRM row, syncs to Stripe, then sets the
        stripe_item_id on the CRM row. Memberships always begin
        on the day this method is called — future start dates
        are not supported. The membership is created discount-free;
        discounts are applied afterward via the apply path.

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

        parent = await self._payment_sync.resolve_parent(member_id)
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

        # ── Step 2: Stripe ────────────────────────────────────
        stripe_item_id: str | None = None
        next_due_date: date | None = None

        try:
            if is_recurring:
                add_item = SyncItem(
                    stripe_price_id=plan_price["stripe_price_id"],
                    member_id=member_id,
                    plan_id=plan_id,
                    prorate=prorate,
                )
                response = await self._payment_sync.update_payments_recurring(
                    member_id,
                    add_ids=[add_item],
                    cancel_ids=[],
                    idempotency_key=idempotency_key,
                    pay_first_invoice_out_of_band=paid_with_cash,
                )
                if response:
                    stripe_item_id = self._extract_stripe_item_id(
                        response,
                        plan_price["stripe_price_id"],
                    )
                    first_item = response.items[0] if response.items else None
                    next_due_date = self._period_end_to_date(
                        first_item.current_period_end if first_item else None,
                    )
            else:
                stripe_item_id = await self._charge_one_time(
                    stripe_customer_id=parent.stripe_customer_id,
                    stripe_price_id=plan_price["stripe_price_id"],
                    gym_id=parent.gym_id,
                    member_id=member_id,
                    plan_id=plan_id,
                    idempotency_key=idempotency_key,
                    paid_with_cash=paid_with_cash,
                )
        except Exception:
            await cleanup_pending_row(
                delete_fn=lambda: self._delete_pending(str(item_id)),
                entity_name="member_membership",
                crm_pk=str(item_id),
            )
            raise

        # ── Step 3: Set stripe_item_id ────────────────────────
        if stripe_item_id:
            set_item_sql = load_sql(
                SQL_DIR / "payment_sync" / "update_stripe_item_id.sql",
            )
            try:
                await self._db_pool.execute_with_retry(
                    set_item_sql,
                    {
                        "item_id": str(item_id),
                        "member_id": str(member_id),
                        "stripe_item_id": stripe_item_id,
                    },
                )
            except Exception as exc:
                raise StripeOrphanError(
                    stripe_resource_type=StripeResourceType.subscription_item,
                    stripe_id=stripe_item_id,
                    crm_pk=str(item_id),
                ) from exc

        # ── Update next_due_date if we got one ────────────────
        if next_due_date:
            await self._update_next_due_date(
                str(item_id),
                str(member_id),
                next_due_date,
            )

    async def preview(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
        prorate: bool = True,
        paid_with_cash: bool = False,
    ) -> PaymentsInvoicePreviewResponse | None:
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
            Invoice preview, or ``None`` for a recurring plan whose
            resulting bucket produces no upcoming invoice.

        Raises:
            ValueError: Same conditions as ``start``.
        """
        plan_price = await self._get_plan_price(gym_id, plan_id, price_id)
        await self._check_no_existing(member_id, gym_id, plan_id)

        parent = await self._payment_sync.resolve_parent(member_id)
        if parent.is_frozen:
            raise ValueError("Cannot start membership: account is frozen")

        if not plan_price["stripe_price_id"]:
            raise ValueError(f"Plan price {plan_price['price_id']} missing stripe_price_id")

        plan_type = PlanType(plan_price["plan_type"])
        is_recurring = plan_type == PlanType.recurring

        if is_recurring:
            add_item = SyncItem(
                stripe_price_id=plan_price["stripe_price_id"],
                member_id=member_id,
                plan_id=plan_id,
                prorate=prorate,
            )
            return await self._payment_sync.preview_update_payments_recurring(
                member_id,
                add_ids=[add_item],
                cancel_ids=[],
            )

        return await self._preview_one_time(
            stripe_customer_id=parent.stripe_customer_id,
            stripe_price_id=plan_price["stripe_price_id"],
            gym_id=parent.gym_id,
        )

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
    ) -> UUID:
        """Insert a new membership row. Returns the generated item_id.

        Memberships are created discount-free — discounts are applied as
        snapshots afterward via the apply path.
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
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().one()
            await session.commit()
        return row["item_id"]

    async def _update_next_due_date(
        self,
        item_id: str,
        member_id: str,
        next_due_date: date,
    ) -> None:
        """Set next_due_date on the membership row after Stripe sync."""
        async with self._db_pool.session() as session:
            await session.execute(
                text(
                    "UPDATE member_memberships_unfiltered "
                    "SET next_due_date = :next_due_date "
                    "WHERE item_id = :item_id AND member_id = :member_id"
                ),
                {
                    "item_id": item_id,
                    "member_id": member_id,
                    "next_due_date": next_due_date,
                },
            )
            await session.commit()

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
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the invoice for a non-recurring plan."""
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(gym_id)
        request = PaymentsInvoicePaymentPreviewRequest(
            stripe_customer_id=stripe_customer_id,
            stripe_price_id=stripe_price_id,
        )
        return await self._payment_service.preview_invoice_payment(
            request,
            stripe_account_id,
        )

    async def _charge_one_time(
        self,
        stripe_customer_id: str,
        stripe_price_id: str,
        gym_id: UUID,
        member_id: UUID,
        plan_id: UUID,
        idempotency_key: UUID,
        paid_with_cash: bool = False,
    ) -> str:
        """Create and pay a one-time invoice for a non-recurring plan.

        Returns:
            The Stripe invoice ID (stored as stripe_item_id).

        Raises:
            PaymentsResourceNotFoundError: If the customer or
                price is not found in Stripe.
        """
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(gym_id)
        metadata = StripeMembershipOneTimeMetadata(
            member_id=member_id,
            gym_id=gym_id,
            plan_id=plan_id,
        )
        request = PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=stripe_customer_id,
            stripe_price_id=stripe_price_id,
            metadata=metadata,
            paid_out_of_band=paid_with_cash,
            idempotency_key=str(idempotency_key),
        )
        response = await self._payment_service.create_invoice_payment(
            request,
            stripe_account_id,
        )
        return response.stripe_invoice_id

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
