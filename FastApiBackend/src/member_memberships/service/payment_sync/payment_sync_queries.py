"""Database queries for the membership payment sync flow."""

from datetime import date
from uuid import UUID

from schema.gym_discount import DiscountMode
from schema.membership_plan import DurationUnit
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    AppliedDiscountSnapshot,
    ParentProfile,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

SYNC_SQL_DIR = SQL_DIR / "payment_sync"
APPLIED_SQL_DIR = SQL_DIR / "applied_discounts"


class PaymentSyncQueries:
    """All database reads/writes for the payment sync flow."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    # ── Resolve Parent ──────────────────────────────────────────

    async def resolve_parent(self, member_id: UUID) -> ParentProfile:
        """Resolve a member to their paying parent profile.

        Follows account_linked_to_id once (single-level hierarchy).

        Raises:
            ValueError: If profile not found or parent has no
                stripe_customer_id.
        """
        sql = load_sql(SYNC_SQL_DIR / "resolve_parent.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(
                f"Profile not found for member_id {member_id}",
            )
        if not row["stripe_customer_id"]:
            raise ValueError(
                f"Parent {row['member_id']} has no stripe_customer_id",
            )
        return ParentProfile(**row)

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
    ) -> list[ActiveMembershipRow]:
        """Get all active recurring memberships for family members."""
        if not family_ids:
            return []

        sql = load_sql(SYNC_SQL_DIR / "get_active_recurring.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        return [self._parse_membership_row(r) for r in rows]

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

    # ── Applied Discount Snapshots ──────────────────────────────

    async def get_applied_discounts(
        self,
        family_ids: list[UUID],
    ) -> list[AppliedDiscountSnapshot]:
        """Read every applied-discount snapshot for a family's memberships.

        Reads the unfiltered base table (service-role): half-synced rows
        (no stripe_coupon_id yet) must still be seen by the sync that
        resolves them.
        """
        if not family_ids:
            return []

        sql = load_sql(APPLIED_SQL_DIR / "get_applied_discounts_by_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        return [self._parse_snapshot_row(r) for r in rows]

    @staticmethod
    def _parse_snapshot_row(row: dict) -> AppliedDiscountSnapshot:
        """Parse a raw DB row into an AppliedDiscountSnapshot."""
        return AppliedDiscountSnapshot(
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

    async def set_snapshot_coupon_id(
        self,
        applied_discount_id: UUID,
        stripe_coupon_id: str,
    ) -> None:
        """Write the sync-resolved coupon back onto one snapshot.

        Service-role writeback to the unfiltered base table: for a ``once``
        snapshot the stored coupon is the consumption-tracking handle; for an
        ongoing snapshot it records the coupon the line is currently using.
        """
        sql = load_sql(APPLIED_SQL_DIR / "set_snapshot_coupon_id.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "applied_discount_id": str(applied_discount_id),
                    "stripe_coupon_id": stripe_coupon_id,
                },
            )
            await session.commit()

    async def stamp_snapshot_consumed(
        self,
        applied_discount_id: UUID,
        end_date: date,
    ) -> None:
        """Stamp end_date on a ``once`` snapshot the sync found consumed.

        Service-role writeback to the unfiltered base table. Only stamps a row
        that does not already carry an end_date (idempotent on re-run).
        """
        sql = load_sql(APPLIED_SQL_DIR / "stamp_snapshot_end_date.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "applied_discount_id": str(applied_discount_id),
                    "end_date": end_date,
                },
            )
            await session.commit()

    # ── Add IDs Interval Resolution ─────────────────────────────

    async def get_price_intervals(
        self,
        stripe_price_ids: list[str],
    ) -> dict[str, tuple[DurationUnit, int]]:
        """Get duration_unit and price for stripe_price_ids.

        Returns:
            Mapping of stripe_price_id -> (duration_unit, price).
        """
        if not stripe_price_ids:
            return {}

        sql = load_sql(SYNC_SQL_DIR / "get_price_intervals.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"stripe_price_ids": stripe_price_ids},
            )
            rows = result.mappings().fetchall()

        return {
            r["stripe_price_id"]: (
                DurationUnit(r["duration_unit"]),
                r["price"],
            )
            for r in rows
        }

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
