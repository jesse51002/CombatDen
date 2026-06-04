"""Database queries for the membership payment sync flow."""

from uuid import UUID

from schema.membership_plan import DurationUnit
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships import SQL_DIR
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    LinkedDiscountInfo,
    ParentProfile,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

SYNC_SQL_DIR = SQL_DIR / "payment_sync"


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
            member_id=UUID(str(row["member_id"])),
            plan_id=UUID(str(row["plan_id"])),
            price_id=UUID(str(row["price_id"])),
            stripe_price_id=row["stripe_price_id"],
            stripe_item_id=row["stripe_item_id"],
            duration_unit=DurationUnit(row["duration_unit"]),
            discount_ids=[UUID(d) for d in (row["discount_ids"] or [])],
            price=row["price"],
        )

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

    # ── Linked Discounts ────────────────────────────────────────

    async def get_linked_discount_ids(
        self,
        family_ids: list[UUID],
    ) -> list[UUID]:
        """Get linked_discount_ids from family member profiles."""
        sql = load_sql(SYNC_SQL_DIR / "get_linked_discount_ids.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        return [UUID(str(r["linked_discount_id"])) for r in rows]

    async def get_discount_details(
        self,
        discount_ids: list[UUID],
    ) -> list[LinkedDiscountInfo]:
        """Fetch Stripe coupon info for discount IDs."""
        sql = load_sql(SYNC_SQL_DIR / "get_discount_details.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"discount_ids": [str(d) for d in discount_ids]},
            )
            rows = result.mappings().fetchall()

        return [
            LinkedDiscountInfo(
                discount_id=UUID(str(r["discount_id"])),
                stripe_coupon_id=r["stripe_coupon_id"],
                dollar_off=r["dollar_off"],
            )
            for r in rows
        ]

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
