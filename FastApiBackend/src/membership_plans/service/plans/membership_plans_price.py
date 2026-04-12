"""Price management and member migration for membership plans."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING
from uuid import UUID

from fastapi import BackgroundTasks
from schema.membership_plan import DurationUnit, PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.membership_plans import SQL_DIR
from src.membership_plans.membership_plans_schemas import (
    MembershipPlanPriceRequest,
    MembershipPlanPriceResponse,
)
from src.membership_plans.service.plans.membership_plans_base import (
    MembershipPlansBase,
)
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_price_schema import (
    PaymentsPriceCreateRequest,
    PaymentsPriceDeactivateRequest,
)
from src.shared.database import DirectDatabasePool
from src.shared.db_first_helpers import cleanup_pending_row
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.member_memberships.service.membership_payment_sync_service import (
        MembershipPaymentSyncService,
    )
    from src.payments.service.payments_stripe_membership_service import (
        PaymentsStripeMembershipService,
    )
    from src.payments.service.payments_stripe_price_service import (
        PaymentsStripePriceService,
    )
    from src.shared.gym_stripe_service import GymStripeService
    from src.shared.stripe_reconciliation.stripe_reconciliation_service import (
        StripeReconciliationService,
    )

logger = logging.getLogger(__name__)


class MembershipPlansPrice(MembershipPlansBase):
    """Set/update plan prices and migrate members."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_membership_service: PaymentsStripeMembershipService,
        stripe_price_service: PaymentsStripePriceService,
        membership_payment_sync_service: MembershipPaymentSyncService,
    ) -> None:
        super().__init__(
            db_pool,
            gym_stripe_service,
            stripe_membership_service,
            stripe_price_service,
        )
        self._payment_sync = membership_payment_sync_service

    # ── Set Price ──────────────────────────────────────────────

    async def set_price(
        self,
        request: MembershipPlanPriceRequest,
    ) -> MembershipPlanPriceResponse:
        """Insert CRM price row, create Stripe Price, then set stripe ID.

        Existing members keep their old price. Use migrate endpoints
        to move them to the new price.

        Args:
            request: Plan ID, gym ID, and new price in cents.

        Returns:
            The newly created price.

        Raises:
            ValueError: If the plan is not found or has no Stripe product.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        plan = await self._get_plan(request.plan_id, request.gym_id)

        stripe_product_id = plan.get("stripe_product_id")
        if not stripe_product_id:
            raise ValueError(
                f"Plan {request.plan_id} has no Stripe product",
            )

        plan_type = PlanType(plan["plan_type"])
        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        # ── Step 1: DB insert (NULL stripe_price_id) ──────────
        insert_sql = load_sql(
            SQL_DIR / "membership_plans_price_insert.sql",
        )
        price_params = {
            "plan_id": str(request.plan_id),
            "gym_id": str(request.gym_id),
            "stripe_price_id": None,
            "price": request.price,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(insert_sql),
                price_params,
            )
            new_price_row = dict(result.mappings().one())
            await session.commit()

        price_id = str(new_price_row["price_id"])

        # ── Step 2: Stripe create ─────────────────────────────
        recurring_interval, recurring_interval_count = self._resolve_interval(plan)

        try:
            stripe_resp = await self._stripe_prices.create_price(
                PaymentsPriceCreateRequest(
                    stripe_product_id=stripe_product_id,
                    unit_amount=request.price,
                    plan_type=plan_type,
                    recurring_interval=recurring_interval,
                    recurring_interval_count=recurring_interval_count,
                    metadata={"crm_price_id": price_id},
                ),
                stripe_account_id,
            )
        except Exception:
            await cleanup_pending_row(
                delete_fn=lambda: self._delete_pending_price(
                    price_id,
                    str(request.plan_id),
                ),
                entity_name="membership_plan_price",
                crm_pk=price_id,
            )
            raise

        # ── Step 3: Set stripe_price_id ───────────────────────
        set_price_sql = load_sql(
            SQL_DIR / "membership_plans_price_set_stripe_price_id.sql",
        )
        try:
            new_price_row = await self._db_pool.execute_with_retry(
                set_price_sql,
                {
                    "price_id": price_id,
                    "plan_id": str(request.plan_id),
                    "stripe_price_id": stripe_resp.stripe_price_id,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.price,
                stripe_id=stripe_resp.stripe_price_id,
                crm_pk=price_id,
            ) from exc

        # ── CRM: deactivate old price ─────────────────────────
        old_price = await self._deactivate_old_price(
            plan_id=request.plan_id,
            gym_id=request.gym_id,
            exclude_price_id=new_price_row["price_id"],
        )

        # ── Stripe: deactivate old price (best-effort) ────────
        if old_price and old_price.get("stripe_price_id"):
            try:
                await self._stripe_prices.deactivate_price(
                    PaymentsPriceDeactivateRequest(
                        stripe_price_id=old_price["stripe_price_id"],
                    ),
                    stripe_account_id,
                )
            except Exception:
                logger.warning(
                    "Failed to deactivate old Stripe price %s (orphaned in Stripe)",
                    old_price["stripe_price_id"],
                    exc_info=True,
                )

        return self._build_price_response(new_price_row)

    # ── Migrate All Members ────────────────────────────────────

    async def migrate_all_members(
        self,
        plan_id: UUID,
        gym_id: UUID,
        background_tasks: BackgroundTasks,
        reconciliation_service: StripeReconciliationService,
    ) -> None:
        """Migrate all active members on a plan to the current price.

        Finds all crm_user_ids with active memberships on this plan
        and queues a background payment sync.

        Args:
            plan_id: The plan whose members to migrate.
            gym_id: The gym owning the plan.
            background_tasks: FastAPI background tasks.
            reconciliation_service: Passed to bulk_payment_sync.

        Raises:
            ValueError: If the plan is not found.
        """
        await self._get_plan(plan_id, gym_id)

        affected = await self._get_affected_crm_user_ids(plan_id)
        if not affected:
            return

        self._run_migration(
            affected,
            background_tasks,
            reconciliation_service,
        )

    # ── Migrate Specific Members ───────────────────────────────

    async def migrate_members(
        self,
        plan_id: UUID,
        gym_id: UUID,
        crm_user_ids: list[UUID],
        background_tasks: BackgroundTasks,
        reconciliation_service: StripeReconciliationService,
    ) -> None:
        """Migrate specific members to the current active price.

        Args:
            plan_id: The plan (validated for existence).
            gym_id: The gym owning the plan.
            crm_user_ids: Explicit list of members to migrate.
            background_tasks: FastAPI background tasks.
            reconciliation_service: Passed to bulk_payment_sync.

        Raises:
            ValueError: If the plan is not found.
        """
        await self._get_plan(plan_id, gym_id)

        if not crm_user_ids:
            return

        self._run_migration(
            crm_user_ids,
            background_tasks,
            reconciliation_service,
        )

    # ── Private ────────────────────────────────────────────────

    def _run_migration(
        self,
        crm_user_ids: list[UUID],
        background_tasks: BackgroundTasks,
        reconciliation_service: StripeReconciliationService,
    ) -> None:
        """Queue a bulk payment sync as a background task."""
        background_tasks.add_task(
            self._payment_sync.bulk_payment_sync,
            crm_user_ids,
            reconciliation_service,
        )

    async def _get_affected_crm_user_ids(
        self,
        plan_id: UUID,
    ) -> list[UUID]:
        """Find crm_user_ids with active memberships on this plan."""
        sql = load_sql(
            SQL_DIR / "membership_plans_get_affected_members.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"plan_id": str(plan_id)},
            )
            rows = result.mappings().fetchall()

        return [UUID(str(r["crm_user_id"])) for r in rows]

    async def _delete_pending_price(
        self,
        price_id: str,
        plan_id: str,
    ) -> None:
        """Hard-delete a pending price row (NULL stripe_price_id)."""
        sql = load_sql(
            SQL_DIR / "membership_plans_price_delete_pending.sql",
        )
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"price_id": price_id, "plan_id": plan_id},
            )
            await session.commit()

    async def _deactivate_old_price(
        self,
        plan_id: UUID,
        gym_id: UUID,
        exclude_price_id: UUID,
    ) -> dict | None:
        """Deactivate old active price rows, excluding the new one.

        Returns:
            The deactivated price row, or None if there was none.
        """
        deactivate_sql = load_sql(
            SQL_DIR / "membership_plans_price_deactivate.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(deactivate_sql),
                {
                    "plan_id": str(plan_id),
                    "gym_id": str(gym_id),
                    "exclude_price_id": str(exclude_price_id),
                },
            )
            row = result.mappings().fetchone()
            await session.commit()

        return dict(row) if row else None

    @staticmethod
    def _resolve_interval(plan: dict) -> tuple[DurationUnit, int]:
        """Determine the Stripe recurring interval from a plan row."""
        plan_type = PlanType(plan["plan_type"])
        if plan_type == PlanType.recurring:
            return DurationUnit.month, 1

        if plan.get("duration_unit") and plan.get("duration_amount"):
            return (
                DurationUnit(plan["duration_unit"]),
                plan["duration_amount"],
            )

        return DurationUnit.month, 1
