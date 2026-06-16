"""Shared dependencies and helpers for membership operations."""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from dateutil.relativedelta import relativedelta
from schema.member_membership import StripeSyncStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsStartRequest,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionResponse,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    from src.shared.gym_stripe_service import GymStripeService
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)


class MemberMembershipsBase:
    """Base class for membership sub-services.

    Holds shared dependencies and reusable query/helper
    methods used across cancel, freeze, start, and
    update_price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
    ) -> None:
        self._db_pool = db_pool
        self._payment_sync = payment_sync_service
        self._gym_stripe = gym_stripe_service

    # ── Shared Queries ─────────────────────────────────────────

    async def _get_membership(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> dict:
        """Fetch membership row for validation and Stripe info.

        Raises:
            ValueError: If the membership is not found.
        """
        get_sql = load_sql(SQL_DIR / "member_memberships_get.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(get_sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Membership not found: item_id={item_id}, member_id={member_id}")
        return dict(row)

    async def _get_sync_status(
        self,
        item_id: UUID,
        member_id: UUID,
    ) -> StripeSyncStatus | None:
        """Read a membership's Stripe-sync status from the unfiltered base.

        DB-first callers use this to VERIFY a sync landed: a pending add flips
        ``not_added`` -> ``applied`` and a cancel flips ``applied`` ->
        ``deleted``. Reads the unfiltered base (the filtered view hides those
        states). Returns ``None`` if the row no longer exists.
        """
        sql = load_sql(SQL_DIR / "member_memberships_sync_status.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.fetchone()
        return StripeSyncStatus(row[0]) if row else None

    async def _get_active_price_for_plan(
        self,
        gym_id: UUID,
        plan_id: UUID,
    ) -> dict:
        """Fetch the plan's currently active price row.

        Shared by the reprice request validation and the reprice executor —
        both target the plan's single ``is_active = true`` price.

        Raises:
            ValueError: If no active price exists for the plan.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_active_price.sql")
        params = {
            "gym_id": str(gym_id),
            "plan_id": str(plan_id),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"No active price for plan: plan_id={plan_id}, gym_id={gym_id}")
        return dict(row)

    async def _get_price_for_plan(
        self,
        gym_id: UUID,
        plan_id: UUID,
        price_id: UUID,
    ) -> dict:
        """Fetch a SPECIFIC price row of a plan by id — active or not.

        The reprice honors the price pinned on its task **as-is**, even if a
        newer price has since become the plan's active one (the user started
        the reprice against the price active then, and a deactivated CRM
        price keeps its usable Stripe price — `plans_price.py` never archives
        a Stripe price). Returns the row (``stripe_price_id`` / ``price`` /
        ``is_active``).

        Raises:
            ValueError: If the price is not a price of this plan.
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_price.sql")
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
                f"Price is not on this plan: price_id={price_id}, "
                f"plan_id={plan_id}, gym_id={gym_id}"
            )
        return dict(row)

    async def _pre_sync_payments(self, member_id: UUID) -> None:
        """Converge the family to a clean DB↔Stripe baseline BEFORE mutating.

        Every lifecycle op runs this first so it never builds a new desired state
        on top of a DB that has drifted from Stripe (e.g. a half-finished prior
        op left a pending or unsettled row). Uses a FRESH idempotency key —
        independent of the operation's own key, since it is a separate converge —
        and default ``proration_behavior`` (``none``), so it reconciles without
        billing. If it raises, the operation aborts before any DB change.
        """
        await self._payment_sync.update_payments_recurring(
            member_id,
            idempotency_key=uuid4(),
        )

    async def _set_sync_status(
        self,
        item_id: UUID,
        member_id: UUID,
        status: StripeSyncStatus,
    ) -> None:
        """Stamp a membership's ``stripe_sync_status`` (e.g. preview staging).

        Used by the preview dry-run to stage ``preview_remove`` then restore the
        prior status. Touches only ``stripe_sync_status``.
        """
        sql = load_sql(SQL_DIR / "set_membership_sync_status.sql")
        params = {
            "item_id": str(item_id),
            "member_id": str(member_id),
            "sync_status": status.value,
        }
        async with self._db_pool.session() as session:
            await session.execute(text(sql), params)
            await session.commit()

    async def _get_plan_prices(
        self,
        gym_id: UUID,
        price_ids: list[UUID],
    ) -> dict[UUID, dict]:
        """Validate every price id is usable, in one read.

        A price belongs to exactly one plan, so the price id alone
        determines the joined plan/price row; the row carries its
        (UUID-normalized) ``plan_id``.

        Returns:
            The joined plan/price row per requested price_id.

        Raises:
            ValueError: If any price is not found, its plan deleted, or the
                price inactive (first offending price).
        """
        sql = load_sql(SQL_DIR / "member_memberships_get_plan_prices.sql")
        params = {
            "gym_id": str(gym_id),
            "price_ids": [str(price_id) for price_id in price_ids],
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows: dict[UUID, dict] = {}
            for mapping in result.mappings():
                row = dict(mapping)
                row["plan_id"] = UUID(str(row["plan_id"]))
                rows[UUID(str(row["price_id"]))] = row

        for price_id in price_ids:
            row = rows.get(price_id)
            if not row:
                raise ValueError(
                    f"Plan/price not found: price_id={price_id}, "
                    f"gym_id={gym_id}"
                )
            if row["plan_is_deleted"]:
                raise ValueError(
                    f"Plan is deleted: plan_id={row['plan_id']}",
                )
            if not row["price_is_active"]:
                raise ValueError(f"Price is not active: price_id={price_id}")
        return rows

    async def _check_no_existing(
        self,
        member_id: UUID,
        gym_id: UUID,
        plan_ids: list[UUID],
    ) -> None:
        """Ensure ONE member has no active/frozen membership on these plans.

        The check is inherently per-member: one member_id, batched only
        across that member's requested plan ids.

        Raises:
            ValueError: If an active or frozen membership already exists on
                any of the plans.
        """
        sql = load_sql(SQL_DIR / "member_memberships_check_existing.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
            "plan_ids": [str(plan_id) for plan_id in plan_ids],
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            existing = {UUID(str(r[0])) for r in result.fetchall()}

        for plan_id in plan_ids:
            if plan_id in existing:
                raise ValueError(
                    f"Active membership already exists: "
                    f"member_id={member_id}, gym_id={gym_id}, "
                    f"plan_id={plan_id}"
                )

    async def _crm_insert(
        self,
        rows: list[dict],
    ) -> dict[tuple[UUID, UUID], UUID]:
        """Insert membership rows in ONE multi-row statement.

        Each row dict carries: member_id, gym_id, plan_id, price_id,
        start_date, end_date, last_paid_date, next_due_date, stripe_item_id,
        prorate, total_price, and optionally sync_status (default
        ``not_added`` — the real start's pending row; the start preview
        passes ``preview_add`` so the dry-run sees it but the real path
        never bills it). All rows appear atomically, or none.

        Returns:
            The generated item_id per (member_id, plan_id) — unique within
            a request (the request validator rejects duplicates).
        """
        sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
        params = {
            "member_ids": [str(r["member_id"]) for r in rows],
            "gym_ids": [str(r["gym_id"]) for r in rows],
            "plan_ids": [str(r["plan_id"]) for r in rows],
            "price_ids": [str(r["price_id"]) for r in rows],
            "start_dates": [r["start_date"] for r in rows],
            "end_dates": [r["end_date"] for r in rows],
            "last_paid_dates": [r["last_paid_date"] for r in rows],
            "next_due_dates": [r["next_due_date"] for r in rows],
            "stripe_item_ids": [r["stripe_item_id"] for r in rows],
            "prorates": [r["prorate"] for r in rows],
            "total_prices": [r["total_price"] for r in rows],
            "sync_statuses": [
                r.get("sync_status", StripeSyncStatus.not_added).value
                for r in rows
            ],
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            ids = {
                (UUID(str(r["member_id"])), UUID(str(r["plan_id"]))): UUID(
                    str(r["item_id"]),
                )
                for r in result.mappings()
            }
            await session.commit()
        return ids

    def _build_pending_rows(
        self,
        request: MemberMembershipsStartRequest,
        plan_prices: dict[UUID, dict],
        start_date: date,
        sync_status: StripeSyncStatus = StripeSyncStatus.not_added,
    ) -> list[dict]:
        """Build the start op's membership insert rows, one per item.

        Shared by the real start (``not_added``) and the staged preview
        (``preview_add``) so the two stage IDENTICAL rows. A non-recurring
        plan with a duration gets its absolute ``end_date`` resolved here.
        """
        rows: list[dict] = []
        for item in request.memberships:
            plan_price = plan_prices[item.price_id]
            end_date: date | None = None
            is_recurring = (
                PlanType(plan_price["plan_type"]) == PlanType.recurring
            )
            if (
                not is_recurring
                and plan_price["duration_amount"]
                and plan_price["duration_unit"]
            ):
                end_date = self._calculate_end_date(
                    start_date,
                    plan_price["duration_amount"],
                    plan_price["duration_unit"],
                )
            rows.append({
                "member_id": item.member_id,
                "gym_id": request.gym_id,
                "plan_id": plan_price["plan_id"],
                "price_id": item.price_id,
                "start_date": start_date,
                "end_date": end_date,
                "last_paid_date": start_date,
                "next_due_date": None,
                "stripe_item_id": None,
                "prorate": request.prorate,
                "total_price": plan_price["price"],
                "sync_status": sync_status,
            })
        return rows

    async def _delete_pending(self, item_ids: list[UUID]) -> None:
        """Hard-delete pending membership rows (NULL stripe_item_id)."""
        if not item_ids:
            return
        sql = load_sql(SQL_DIR / "member_memberships_delete_pending.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"item_ids": [str(item_id) for item_id in item_ids]},
            )
            await session.commit()

    # ── Static Helpers ─────────────────────────────────────────

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

    @staticmethod
    def _extract_stripe_item_id(
        response: PaymentsSubscriptionResponse,
        stripe_price_id: str,
    ) -> str | None:
        """Find the stripe_item_id matching a price in the response."""
        for item in response.items:
            if item.stripe_price_id == stripe_price_id:
                return item.stripe_subscription_item_id
        return None

    @staticmethod
    def _period_end_to_date(
        current_period_end: int | None,
    ) -> date | None:
        """Convert a Stripe Unix timestamp to a date."""
        if current_period_end is None:
            return None
        return datetime.fromtimestamp(
            current_period_end,
            tz=UTC,
        ).date()
