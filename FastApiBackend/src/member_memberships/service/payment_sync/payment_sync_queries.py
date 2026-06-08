"""Database queries for the membership payment sync flow."""

import json
from collections import defaultdict
from datetime import date
from uuid import UUID

from schema.gym_discount import DiscountMode
from schema.member_membership import StripeSyncStatus
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

# Sync statuses a billing read never includes. The REAL path drops every
# `preview_*` (staging); the PREVIEW path keeps `preview_add` (the staged
# additions it's previewing) but still drops `preview_remove`. `deleted` is
# never billed by either.
_EXCLUDED_REAL = [
    StripeSyncStatus.deleted.value,
    StripeSyncStatus.preview_add.value,
    StripeSyncStatus.preview_remove.value,
]
_EXCLUDED_PREVIEW = [
    StripeSyncStatus.deleted.value,
    StripeSyncStatus.preview_remove.value,
]


def _excluded_statuses(preview: bool) -> list[str]:
    """The sync-status values the read must exclude (real vs preview)."""
    return _EXCLUDED_PREVIEW if preview else _EXCLUDED_REAL


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
        preview: bool = False,
    ) -> list[ActiveMembershipRow]:
        """Get the family's desired recurring memberships, each with discounts.

        One call: reads the desired recurring memberships, then their **active**
        applied discounts (the read excludes any past its end_date as of
        ``today`` — the gym-timezone date), and attaches each membership's
        discounts onto its row (the discount rides the membership).

        ``preview`` selects which rows the build sees: the **real** path drops
        every ``preview_*`` staged row; the **preview** path keeps ``preview_add``
        (so the dry-run reflects staged additions) and drops ``preview_remove``.
        """
        if not family_ids:
            return []

        sql = load_sql(SYNC_SQL_DIR / "get_active_recurring.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_ids": [str(uid) for uid in family_ids],
                    "excluded_statuses": _excluded_statuses(preview),
                },
            )
            rows = result.mappings().fetchall()

        memberships = [self._parse_membership_row(r) for r in rows]
        discounts_by_item = await self._get_discounts_by_item(
            family_ids,
            today,
            preview,
        )
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
            price=row["price"],
            stripe_item_id=row["stripe_item_id"],
            duration_unit=DurationUnit(row["duration_unit"]),
        )

    # ── Applied Discounts ───────────────────────────────────────

    async def _get_discounts_by_item(
        self,
        family_ids: list[UUID],
        today: date,
        preview: bool = False,
    ) -> dict[UUID, list[AppliedDiscount]]:
        """Read the family's active applied discounts, grouped by membership.

        Keyed by ``item_id``. The query excludes any discount past its end_date
        as of ``today`` (the gym-timezone date) — the engine's date-lifetime
        cutoff lives in the SQL, not in code — and the ``preview_*`` staging rows
        per the ``preview`` flag (real drops both; preview keeps ``preview_add``).
        Reads the unfiltered base table (service-role): half-synced rows (no
        stripe_coupon_id yet) must still be seen by the sync that resolves them.
        """
        sql = load_sql(APPLIED_SQL_DIR / "get_applied_discounts_by_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "member_ids": [str(uid) for uid in family_ids],
                    "today": today,
                    "excluded_statuses": _excluded_statuses(preview),
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
        """Write the sync-resolved coupon + 'applied' status onto one discount.

        Service-role writeback to the unfiltered base table: stamps the coupon
        (for a ``once`` discount the consumption-tracking handle; for an ongoing
        discount the coupon the line is currently using) and marks the row
        ``stripe_sync_status = 'applied'`` — synced and live on Stripe.
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

    async def apply_membership_sync(
        self,
        item_id: UUID,
        member_id: UUID,
        stripe_item_id: str,
        next_due_date: date | None,
    ) -> None:
        """Stamp the sync result onto one membership row (real path).

        Writes the live Stripe line id, the next_due_date, and
        ``stripe_sync_status = 'applied'`` — confirming the row is live on
        Stripe. The line id is NULL→value on first sync (the immutable trigger
        allows that one transition; echoing the same value is a no-op).
        """
        sql = load_sql(SYNC_SQL_DIR / "apply_membership_sync.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {
                    "item_id": str(item_id),
                    "member_id": str(member_id),
                    "stripe_item_id": stripe_item_id,
                    "next_due_date": next_due_date,
                },
            )
            await session.commit()

    async def set_member_post_discount_prices(
        self,
        member_amounts: dict[UUID, int],
    ) -> None:
        """Write each membership's own post-discount price onto total_price.

        ``member_amounts`` maps ``item_id → cents`` (computed at build time by
        ``PaymentSyncDiscounts``). Real path only; a no-op when empty.
        """
        if not member_amounts:
            return
        payload = [
            {"item_id": str(item_id), "amount": amount}
            for item_id, amount in member_amounts.items()
        ]
        sql = load_sql(SYNC_SQL_DIR / "set_member_post_discount_prices.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"member_amounts": json.dumps(payload)},
            )
            await session.commit()

    async def get_cancelled_recurring(
        self,
        family_ids: list[UUID],
    ) -> dict[UUID, str]:
        """Read cancelled recurring rows still carrying a Stripe line id.

        Returns ``item_id → stripe_item_id`` for cancelled rows not yet marked
        ``deleted`` — the writeback diffs these against the live subscription to
        confirm removal and stamp ``deleted``.
        """
        if not family_ids:
            return {}

        sql = load_sql(SYNC_SQL_DIR / "get_cancelled_recurring.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"member_ids": [str(uid) for uid in family_ids]},
            )
            rows = result.mappings().fetchall()

        return {UUID(str(r["item_id"])): r["stripe_item_id"] for r in rows}

    async def mark_memberships_deleted(
        self,
        item_ids: list[UUID],
    ) -> None:
        """Stamp ``stripe_sync_status = 'deleted'`` on the given rows.

        The cancelled rows the writeback confirmed are gone from the live
        subscription — recorded so a cancelled row is never mistaken for one
        still billing.
        """
        if not item_ids:
            return

        sql = load_sql(SYNC_SQL_DIR / "mark_membership_deleted.sql")
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"item_ids": [str(i) for i in item_ids]},
            )
            await session.commit()
