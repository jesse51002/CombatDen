"""Database queries for the membership payment sync flow."""

from collections import defaultdict
from datetime import date
from uuid import UUID

from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    AppliedDiscount,
    OnceDiscount,
)
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

SYNC_SQL_DIR = SQL_DIR / "payment_sync"
APPLIED_SQL_DIR = SQL_DIR / "applied_discounts"


class PaymentSyncQueries:
    """All database reads/writes for the payment sync flow."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    # ── Family Members ──────────────────────────────────────────

    async def get_family_ids(
        self,
        parent: ParentProfile,
    ) -> list[UUID]:
        """Get all family member IDs (parent + linked children)."""
        sql = load_sql(SYNC_SQL_DIR / "get_family_ids.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "parent_member_id": str(parent.member_id),
                    "gym_id": str(parent.gym_id),
                },
            )
            rows = result.mappings().fetchall()

        return [UUID(str(r["member_id"])) for r in rows]

    # ── Active Memberships ──────────────────────────────────────

    async def get_active_memberships(
        self,
        family_ids: list[UUID],
        today: date,
    ) -> list[ActiveMembershipRow]:
        """Get the family's active recurring memberships, each with discounts.

        One call: reads the active recurring memberships, then their **active**
        applied discounts (the read excludes any past its end_date as of
        ``today`` — the gym-timezone date), and attaches each membership's
        discounts onto its row (the discount rides the membership).
        """
        if not family_ids:
            return []

        sql = load_sql(SYNC_SQL_DIR / "get_active_recurring.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        memberships = [self._parse_membership_row(r) for r in rows]
        discounts_by_item = await self._get_discounts_by_item(family_ids, today)
        for membership in memberships:
            membership.discounts = discounts_by_item.get(membership.item_id, [])
        return memberships

    @staticmethod
    def _parse_membership_row(row: dict) -> ActiveMembershipRow:
        """Parse a raw DB row into an ActiveMembershipRow."""
        return ActiveMembershipRow(
            item_id=UUID(str(row["item_id"])),
            member_id=UUID(str(row["member_id"])),
            plan_id=UUID(str(row["plan_id"])),
            price_id=UUID(str(row["price_id"])),
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            duration_unit=DurationUnit(row["duration_unit"]),
            price=row["price"],
        )

    # ── Applied Discounts ───────────────────────────────────────

    async def _get_discounts_by_item(
        self,
        family_ids: list[UUID],
        today: date,
    ) -> dict[UUID, list[AppliedDiscount]]:
        """Read the family's active applied discounts, grouped by membership.

        Keyed by ``item_id``. The query excludes any discount past its end_date
        as of ``today`` (the gym-timezone date) — the engine's date-lifetime
        cutoff lives in the SQL, not in code. Reads the unfiltered base table
        (service-role): half-synced rows (no stripe_coupon_id yet) must still be
        seen by the sync that resolves them.
        """
        sql = load_sql(APPLIED_SQL_DIR / "get_applied_discounts_by_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_ids": [str(uid) for uid in family_ids],
                    "today": today,
                },
            )
            rows = result.mappings().fetchall()

        grouped: dict[UUID, list[AppliedDiscount]] = defaultdict(list)
        for row in rows:
            discount = self._parse_applied_discount_row(row)
            grouped[discount.item_id].append(discount)
        return dict(grouped)

    async def get_unconsumed_once_discounts(
        self,
        family_ids: list[UUID],
    ) -> list[OnceDiscount]:
        """Read the family's attached-but-unconsumed ``once`` discounts.

        Only ``once`` rows with no end_date and a coupon already attached — the
        candidates the sync checks against the live subscription. Reads the
        unfiltered base tables (service-role).
        """
        if not family_ids:
            return []

        sql = load_sql(APPLIED_SQL_DIR / "get_unconsumed_once_discounts.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        return [OnceDiscount(**r) for r in rows]

    @staticmethod
    def _parse_applied_discount_row(row: dict) -> AppliedDiscount:
        """Parse a raw DB row into an AppliedDiscount."""
        return AppliedDiscount(
            applied_discount_id=UUID(str(row["applied_discount_id"])),
            item_id=UUID(str(row["item_id"])),
            member_id=UUID(str(row["member_id"])),
            plan_id=UUID(str(row["plan_id"])),
            stripe_item_id=row["stripe_item_id"],
            discount_mode=DiscountMode(row["discount_mode"]),
            percentage_off=row["percentage_off"],
            dollar_off=row["dollar_off"],
            end_date=row["end_date"],
            stripe_coupon_id=row["stripe_coupon_id"],
        )

    async def set_applied_discount_coupon_id(
        self,
        applied_discount_id: UUID,
        stripe_coupon_id: str,
    ) -> None:
        """Write the sync-resolved coupon back onto one applied discount.

        Service-role writeback to the unfiltered base table: for a ``once``
        discount the stored coupon is the consumption-tracking handle; for an
        ongoing discount it records the coupon the line is currently using.
        """
        sql = load_sql(APPLIED_SQL_DIR / "set_applied_discount_coupon_id.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "applied_discount_id": str(applied_discount_id),
                    "stripe_coupon_id": stripe_coupon_id,
                },
            )
            await session.commit()

    async def mark_once_consumed(
        self,
        applied_discount_ids: list[UUID],
        end_date: date,
    ) -> None:
        """Stamp end_date on the ``once`` discounts the sync found consumed.

        Service-role writeback to the unfiltered base table — stamps the whole
        consumed set in one statement. Only rows without an end_date are touched
        (idempotent on re-run).
        """
        sql = load_sql(APPLIED_SQL_DIR / "mark_once_consumed.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "applied_discount_ids": [str(i) for i in applied_discount_ids],
                    "end_date": end_date,
                },
            )
            await session.commit()

    # ── Write Back ──────────────────────────────────────────────

    async def update_profile_sub_id(
        self,
        member_id: UUID,
        stripe_sub_id_month: str | None,
    ) -> None:
        """Write stripe_sub_id_month back to the parent profile.

        Args:
            member_id: The parent profile to update.
            stripe_sub_id_month: The Stripe subscription ID, or
                None if cancelled.
        """
        sql = load_sql(SYNC_SQL_DIR / "update_profile_sub_ids.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "member_id": str(member_id),
                    "stripe_sub_id_month": stripe_sub_id_month,
                },
            )
            await session.commit()
