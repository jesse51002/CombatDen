"""Unit tests for the summary key/value computation.

``_summary_rows`` is pure given the already-fetched row lists (it never touches
the pool), so it is exercised directly with fabricated rows. Locks the pinned
money math (gross / refunds / net + the cash vs non-cash split), the counts,
and the key ordering (period, generated_at, money, movement, operations).
"""

from datetime import date
from decimal import Decimal

from src.reports.service.reports_period_service import (
    ReportsPeriodService,
    _ReportWindow,
)


def _window() -> _ReportWindow:
    return _ReportWindow(
        all_time=False,
        start_utc=None,
        end_utc=None,
        start_local=date(2026, 6, 1),
        end_local=date(2026, 7, 1),
        as_of_date=date(2026, 6, 30),
        period_slug="2026-06",
        label="2026-06",
    )


def _pay(kind: str, status: str, method: str | None, amount: int) -> dict:
    return {
        "kind": kind,
        "status": status,
        "payment_method_type": method,
        "amount": amount,
    }


class TestSummaryRows:
    """The full pinned key set with a representative dataset."""

    def _summary(self) -> dict:
        svc = ReportsPeriodService(db_pool=None)  # type: ignore[arg-type]
        payments = [
            _pay("payment", "succeeded", "cash", 2000),
            _pay("payment", "succeeded", "card", 3000),
            _pay("payment", "succeeded", "us_bank_account", 1000),
            _pay("payment", "failed", "card", 9999),  # excluded (not succeeded)
            _pay("refund", "succeeded", "card", -500),
            _pay("refund", "failed", "card", -100),  # excluded
        ]
        invoices = [
            {"status": "paid"},
            {"status": "paid"},
            {"status": "open"},
        ]
        changes = [
            {"change_type": "started"},
            {"change_type": "started"},
            {"change_type": "cancelled"},
            {"change_type": "ended"},
        ]
        new_members = [{"member_id": "m1"}, {"member_id": "m2"}]
        attendance = [
            {"member_id": "a"},
            {"member_id": "a"},
            {"member_id": "b"},
        ]
        class_stats = [
            {"signup_count": 3},
            {"signup_count": 2},
            {"signup_count": 0},
        ]
        rows = svc._summary_rows(
            _window(),
            payments,
            invoices,
            changes,
            new_members,
            attendance,
            class_stats,
            active_count=42,
        )
        self._rows = rows
        return {key: value for key, value in rows}

    def test_ordering_period_then_generated_at(self) -> None:
        self._summary()
        assert self._rows[0][0] == "period"
        assert self._rows[1][0] == "generated_at"

    def test_money_block(self) -> None:
        s = self._summary()
        assert s["gross_revenue"] == Decimal("60.00")
        assert s["refunds"] == Decimal("-5.00")
        assert s["net_revenue"] == Decimal("55.00")
        assert s["collected_cash"] == Decimal("20.00")
        assert s["collected_noncash"] == Decimal("40.00")
        # Identity: cash + non-cash == gross.
        assert s["collected_cash"] + s["collected_noncash"] == s["gross_revenue"]
        assert s["succeeded_payments"] == 3
        assert s["succeeded_refunds"] == 1

    def test_movement_block(self) -> None:
        s = self._summary()
        assert s["new_members"] == 2
        assert s["memberships_started"] == 2
        assert s["memberships_cancelled"] == 1
        assert s["memberships_ended"] == 1
        assert s["active_memberships_at_period_end_incl_frozen"] == 42

    def test_operations_block(self) -> None:
        s = self._summary()
        assert s["total_check_ins"] == 3
        assert s["unique_attendees"] == 2
        assert s["sign_ups"] == 5
        assert s["invoices_paid"] == 2
        assert s["invoices_open"] == 1

    def test_generated_at_is_iso_utc(self) -> None:
        s = self._summary()
        # ISO-8601 with a timezone offset (UTC).
        assert "T" in s["generated_at"]
        assert s["generated_at"].endswith("+00:00")
