"""Period (monthly / all-time) operational report — the human-facing zip.

Financial + membership-movement + attendance/class stats for one gym over a
calendar month (or all-time when no month is given). Human-facing conventions:
decimal-dollar money (converted from stored cents at the CSV boundary only),
gym-local datetimes (``*_local`` headers), a computed ``summary.csv``, and
``utf-8-sig`` encoding (handled by the zip builder).

Reads the FILTERED views (``member_memberships`` / ``membership_plans``) so the
counts match what the CRM screens show; the full export reads the unfiltered
base tables for completeness, so small count differences between the two
artifacts are expected.
"""

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID
from zoneinfo import ZoneInfo

from dateutil.relativedelta import relativedelta
from schema.member_charge import ChargeKind, ChargeStatus
from schema.member_invoice import InvoiceStatus
from sqlalchemy import text

from src.reports import SQL_DIR
from src.reports.schema.reports_schema import (
    ReportMembershipChange,
    ReportMonth,
)
from src.reports.service.reports_filenames import report_filename
from src.reports.service.reports_zip_builder import CsvCell, ReportsZipBuilder
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

# Cents-per-dollar and the 2-decimal money quantum for the CSV boundary.
_CENTS_PER_DOLLAR = Decimal(100)
_MONEY_QUANTUM = Decimal("0.01")

# The payment_method_type value for a cash charge (member_charges stores it as a
# free VARCHAR -- 'cash' | 'card' | 'us_bank_account' | ...). Everything that is
# NOT this (card, ACH, NULL) counts as non-cash in the collected_* split.
_CASH_PAYMENT_METHOD = "cash"

# CSV headers — a v1 contract. Money columns are decimal dollars; ``*_local``
# columns are gym-local wall-clock datetimes.
_SUMMARY_HEADER = ("metric", "value")
_PAYMENTS_HEADER = (
    "charge_time_local", "charge_id", "invoice_id", "kind", "status",
    "amount", "currency", "payment_method_type", "card_last_four",
    "payer_member_id", "payer_first_name", "payer_last_name",
)
_INVOICES_HEADER = (
    "invoice_time_local", "invoice_id", "status", "total_amount", "currency",
    "payer_member_id", "payer_first_name", "payer_last_name", "beneficiaries",
)
_LINE_ITEMS_HEADER = (
    "invoice_time_local", "invoice_id", "line_item_id", "item_type", "name",
    "amount", "quantity", "item_id",
)
_INVOICE_DISCOUNTS_HEADER = (
    "invoice_time_local", "invoice_id", "applied_discount_id", "line_item_id",
    "amount_off", "stripe_coupon_id", "discount_id",
)
_MEMBERSHIP_CHANGES_HEADER = (
    "change_date", "change_type", "item_id", "member_id",
    "member_first_name", "member_last_name", "plan_id", "plan_name",
)
_NEW_MEMBERS_HEADER = (
    "created_at_local", "member_id", "first_name", "last_name", "email",
)
_ATTENDANCE_HEADER = (
    "occurred_at_local", "member_id", "member_first_name", "member_last_name",
    "class_id", "class_name", "original_date", "original_time",
)
_CLASS_STATS_HEADER = (
    "class_id", "class_name", "is_active", "is_deleted",
    "check_in_count", "distinct_members", "signup_count",
)


@dataclass(frozen=True)
class _ReportWindow:
    """The resolved report window: bound params + labels."""

    all_time: bool
    start_utc: datetime | None
    end_utc: datetime | None
    start_local: date | None
    end_local: date | None
    as_of_date: date
    period_slug: str
    label: str


class ReportsPeriodService:
    """Builds the period operational report zip for a gym."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def build_report(
        self,
        gym_id: UUID,
        report_month: ReportMonth | None,
    ) -> tuple[str, bytes]:
        """Build the report.

        Args:
            gym_id: The gym to report on.
            report_month: The month to report, or ``None`` for all-time.

        Returns:
            ``(filename, zip_bytes)`` — the download name + the in-memory zip.
        """
        gym = await self._load_gym(gym_id)
        tz = ZoneInfo(gym["timezone"])
        window = self._compute_window(tz, report_month)

        ts_params = self._ts_params(gym_id, window)
        date_params = self._date_params(gym_id, window)

        payments = await self._fetch("report_payments.sql", ts_params)
        invoices = await self._fetch("report_invoices.sql", ts_params)
        line_items = await self._fetch("report_invoice_line_items.sql", ts_params)
        discounts = await self._fetch("report_invoice_discounts.sql", ts_params)
        changes = await self._fetch("report_membership_changes.sql", date_params)
        new_members = await self._fetch("report_new_members.sql", ts_params)
        attendance = await self._fetch("report_attendance.sql", ts_params)
        class_stats = await self._fetch("report_class_stats.sql", ts_params)
        active_count = await self._fetch_active_count(gym_id, window)

        builder = ReportsZipBuilder()
        builder.add_csv(
            "summary.csv",
            _SUMMARY_HEADER,
            self._summary_rows(
                window,
                payments,
                invoices,
                changes,
                new_members,
                attendance,
                class_stats,
                active_count,
            ),
        )
        builder.add_csv(
            "payments.csv",
            _PAYMENTS_HEADER,
            [self._payment_row(r, tz) for r in payments],
        )
        builder.add_csv(
            "invoices.csv",
            _INVOICES_HEADER,
            [self._invoice_row(r, tz) for r in invoices],
        )
        builder.add_csv(
            "invoice_line_items.csv",
            _LINE_ITEMS_HEADER,
            [self._line_item_row(r, tz) for r in line_items],
        )
        builder.add_csv(
            "invoice_discounts.csv",
            _INVOICE_DISCOUNTS_HEADER,
            [self._invoice_discount_row(r, tz) for r in discounts],
        )
        builder.add_csv(
            "membership_changes.csv",
            _MEMBERSHIP_CHANGES_HEADER,
            [self._membership_change_row(r) for r in changes],
        )
        builder.add_csv(
            "new_members.csv",
            _NEW_MEMBERS_HEADER,
            [self._new_member_row(r, tz) for r in new_members],
        )
        builder.add_csv(
            "attendance.csv",
            _ATTENDANCE_HEADER,
            [self._attendance_row(r, tz) for r in attendance],
        )
        builder.add_csv(
            "class_stats.csv",
            _CLASS_STATS_HEADER,
            [self._class_stat_row(r) for r in class_stats],
        )

        filename = report_filename(
            gym["gym_name"], gym_id, window.period_slug
        )
        return filename, builder.finish()

    # ── window ────────────────────────────────────────────────────────

    def _compute_window(
        self,
        tz: ZoneInfo,
        report_month: ReportMonth | None,
    ) -> _ReportWindow:
        """Resolve the gym-local month window into UTC + local-date binds.

        The month is the gym-local half-open range ``[1st 00:00, next 1st
        00:00)`` converted to UTC instants for timestamptz columns; DATE
        columns compare against the gym-local period dates. All-time skips the
        window entirely (the SQL's all-time flag short-circuits the predicate).
        """
        now_local = datetime.now(UTC).astimezone(tz)
        if report_month is None:
            return _ReportWindow(
                all_time=True,
                start_utc=None,
                end_utc=None,
                start_local=None,
                end_local=None,
                as_of_date=now_local.date(),
                period_slug="all-time",
                label="all-time",
            )

        year, month = report_month.year, report_month.month
        start_local = date(year, month, 1)
        end_local = start_local + relativedelta(months=1)
        start_utc = datetime(year, month, 1, tzinfo=tz).astimezone(UTC)
        end_utc = datetime(
            end_local.year, end_local.month, end_local.day, tzinfo=tz
        ).astimezone(UTC)
        # Last gym-local date of the month (the as-of date for the active count).
        as_of_date = end_local - timedelta(days=1)
        period_slug = f"{year:04d}-{month:02d}"
        is_current = now_local.year == year and now_local.month == month
        label = (
            f"{period_slug} (month to date)" if is_current else period_slug
        )
        return _ReportWindow(
            all_time=False,
            start_utc=start_utc,
            end_utc=end_utc,
            start_local=start_local,
            end_local=end_local,
            as_of_date=as_of_date,
            period_slug=period_slug,
            label=label,
        )

    def _ts_params(self, gym_id: UUID, window: _ReportWindow) -> dict:
        """Bind params for the timestamptz-windowed queries."""
        return {
            "gym_id": str(gym_id),
            "all_time": window.all_time,
            "start_utc": window.start_utc,
            "end_utc": window.end_utc,
        }

    def _date_params(self, gym_id: UUID, window: _ReportWindow) -> dict:
        """Bind params for the DATE-windowed query (membership changes)."""
        return {
            "gym_id": str(gym_id),
            "all_time": window.all_time,
            "start_local": window.start_local,
            "end_local": window.end_local,
        }

    # ── reads ─────────────────────────────────────────────────────────

    async def _load_gym(self, gym_id: UUID) -> dict:
        """Load the gym's name + timezone."""
        sql = load_sql(SQL_DIR / "reports_gym.sql")
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Gym not found")
        return dict(row)

    async def _fetch(self, sql_file: str, params: dict) -> list[dict]:
        """Run a report query, returning its rows as dicts."""
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]

    async def _fetch_active_count(
        self,
        gym_id: UUID,
        window: _ReportWindow,
    ) -> int:
        """Count memberships active (incl. frozen) as of the period-end date."""
        sql = load_sql(SQL_DIR / "report_active_memberships_at.sql")
        params = {"gym_id": str(gym_id), "as_of_date": window.as_of_date}
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return int(row["active_count"]) if row else 0

    # ── summary ───────────────────────────────────────────────────────

    def _summary_rows(
        self,
        window: _ReportWindow,
        payments: list[dict],
        invoices: list[dict],
        changes: list[dict],
        new_members: list[dict],
        attendance: list[dict],
        class_stats: list[dict],
        active_count: int,
    ) -> list[tuple[CsvCell, ...]]:
        """Compute the summary key/value rows with the pinned money math.

        gross = Σ amount of succeeded PAYMENT charges; refunds = Σ amount of
        succeeded REFUND charges (stored ≤ 0); net = gross + refunds (addition,
        because refunds are already negative). The gross is also split into
        cash vs non-cash collections (cash + non-cash == gross). Ordering:
        period, generated_at, the money block, the movement block, then the
        operations block.
        """
        succeeded_payment_rows = [
            r
            for r in payments
            if r["kind"] == ChargeKind.payment
            and r["status"] == ChargeStatus.succeeded
        ]
        gross_cents = sum(r["amount"] for r in succeeded_payment_rows)
        cash_cents = sum(
            r["amount"]
            for r in succeeded_payment_rows
            if r["payment_method_type"] == _CASH_PAYMENT_METHOD
        )
        noncash_cents = gross_cents - cash_cents
        refund_cents = sum(
            r["amount"]
            for r in payments
            if r["kind"] == ChargeKind.refund
            and r["status"] == ChargeStatus.succeeded
        )
        net_cents = gross_cents + refund_cents
        succeeded_refunds = sum(
            1
            for r in payments
            if r["kind"] == ChargeKind.refund
            and r["status"] == ChargeStatus.succeeded
        )
        started = sum(
            1
            for r in changes
            if r["change_type"] == ReportMembershipChange.started
        )
        cancelled = sum(
            1
            for r in changes
            if r["change_type"] == ReportMembershipChange.cancelled
        )
        ended = sum(
            1
            for r in changes
            if r["change_type"] == ReportMembershipChange.ended
        )
        invoices_paid = sum(
            1 for r in invoices if r["status"] == InvoiceStatus.paid
        )
        invoices_open = sum(
            1 for r in invoices if r["status"] == InvoiceStatus.open
        )
        unique_attendees = len({r["member_id"] for r in attendance})
        sign_ups = sum(r["signup_count"] for r in class_stats)
        generated_at = datetime.now(UTC).isoformat()
        return [
            ("period", window.label),
            ("generated_at", generated_at),
            # ── money ──
            ("gross_revenue", self._to_dollars(gross_cents)),
            ("refunds", self._to_dollars(refund_cents)),
            ("net_revenue", self._to_dollars(net_cents)),
            ("collected_cash", self._to_dollars(cash_cents)),
            ("collected_noncash", self._to_dollars(noncash_cents)),
            ("succeeded_payments", len(succeeded_payment_rows)),
            ("succeeded_refunds", succeeded_refunds),
            # ── membership movement ──
            ("new_members", len(new_members)),
            ("memberships_started", started),
            ("memberships_cancelled", cancelled),
            ("memberships_ended", ended),
            ("active_memberships_at_period_end_incl_frozen", active_count),
            # ── operations ──
            ("total_check_ins", len(attendance)),
            ("unique_attendees", unique_attendees),
            ("sign_ups", sign_ups),
            ("invoices_paid", invoices_paid),
            ("invoices_open", invoices_open),
        ]

    # ── row transforms ────────────────────────────────────────────────

    def _payment_row(self, r: dict, tz: ZoneInfo) -> tuple[CsvCell, ...]:
        return (
            self._local(r["charge_time"], tz),
            r["charge_id"],
            r["invoice_id"],
            r["kind"],
            r["status"],
            self._to_dollars(r["amount"]),
            r["currency"],
            r["payment_method_type"],
            r["card_last_four"],
            r["paid_by_member_id"],
            r["payer_first_name"],
            r["payer_last_name"],
        )

    def _invoice_row(self, r: dict, tz: ZoneInfo) -> tuple[CsvCell, ...]:
        return (
            self._local(r["invoice_time"], tz),
            r["invoice_id"],
            r["status"],
            self._to_dollars(r["total_amount"]),
            r["currency"],
            r["paid_by_member_id"],
            r["payer_first_name"],
            r["payer_last_name"],
            r["beneficiaries"],
        )

    def _line_item_row(self, r: dict, tz: ZoneInfo) -> tuple[CsvCell, ...]:
        return (
            self._local(r["invoice_time"], tz),
            r["invoice_id"],
            r["line_item_id"],
            r["item_type"],
            r["name"],
            self._to_dollars(r["amount"]),
            r["quantity"],
            r["item_id"],
        )

    def _invoice_discount_row(
        self, r: dict, tz: ZoneInfo
    ) -> tuple[CsvCell, ...]:
        return (
            self._local(r["invoice_time"], tz),
            r["invoice_id"],
            r["applied_discount_id"],
            r["line_item_id"],
            self._to_dollars(r["amount_off"]),
            r["stripe_coupon_id"],
            r["discount_id"],
        )

    def _membership_change_row(self, r: dict) -> tuple[CsvCell, ...]:
        return (
            r["change_date"],
            r["change_type"],
            r["item_id"],
            r["member_id"],
            r["member_first_name"],
            r["member_last_name"],
            r["plan_id"],
            r["plan_name"],
        )

    def _new_member_row(self, r: dict, tz: ZoneInfo) -> tuple[CsvCell, ...]:
        return (
            self._local(r["created_at"], tz),
            r["member_id"],
            r["first_name"],
            r["last_name"],
            r["email"],
        )

    def _attendance_row(self, r: dict, tz: ZoneInfo) -> tuple[CsvCell, ...]:
        return (
            self._local(r["occurred_at"], tz),
            r["member_id"],
            r["member_first_name"],
            r["member_last_name"],
            r["class_id"],
            r["class_name"],
            r["original_date"],
            r["original_time"],
        )

    def _class_stat_row(self, r: dict) -> tuple[CsvCell, ...]:
        return (
            r["class_id"],
            r["class_name"],
            r["is_active"],
            r["is_deleted"],
            r["check_in_count"],
            r["distinct_members"],
            r["signup_count"],
        )

    # ── formatting helpers ────────────────────────────────────────────

    @staticmethod
    def _to_dollars(cents: int) -> Decimal:
        """Convert stored cents to a 2-decimal dollar amount (numeric cell)."""
        return (Decimal(cents) / _CENTS_PER_DOLLAR).quantize(_MONEY_QUANTUM)

    @staticmethod
    def _local(value: datetime | None, tz: ZoneInfo) -> str | None:
        """Render a UTC timestamp as a gym-local wall-clock string."""
        if value is None:
            return None
        return value.astimezone(tz).strftime("%Y-%m-%d %H:%M:%S")
