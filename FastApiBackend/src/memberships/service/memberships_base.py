"""Shared dependencies and helpers for membership operations."""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING
from uuid import UUID, uuid4

from dateutil.relativedelta import relativedelta
from schema.member_membership import StripeSyncStatus
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
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
        real path never bills it.
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
