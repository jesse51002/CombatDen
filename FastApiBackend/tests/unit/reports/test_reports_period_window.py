"""Unit tests for the period service's window math + dollar formatting.

Pure logic (``_compute_window`` / ``_to_dollars`` never touch the db_pool), so
the service is constructed with a ``None`` pool. The DST cases are the
load-bearing ones: the gym-local month boundary must convert to the correct UTC
instant on BOTH sides of a US DST transition.
"""

from datetime import UTC, datetime
from decimal import Decimal
from zoneinfo import ZoneInfo

from src.reports.schema.reports_schema import ReportMonth
from src.reports.service.reports_period_service import ReportsPeriodService

_CHICAGO = ZoneInfo("America/Chicago")


def _service() -> ReportsPeriodService:
    return ReportsPeriodService(db_pool=None)  # type: ignore[arg-type]


class TestComputeWindow:
    """Gym-local month -> UTC / local-date binds."""

    def test_all_time_skips_the_window(self) -> None:
        window = _service()._compute_window(_CHICAGO, None)
        assert window.all_time is True
        assert window.start_utc is None
        assert window.end_utc is None
        assert window.start_local is None
        assert window.end_local is None
        assert window.period_slug == "all-time"
        assert window.label == "all-time"

    def test_plain_month_boundaries(self) -> None:
        # June 2026 is fully inside CDT (UTC-5).
        window = _service()._compute_window(_CHICAGO, ReportMonth(2026, 6))
        assert window.all_time is False
        assert window.start_utc == datetime(2026, 6, 1, 5, 0, tzinfo=UTC)
        assert window.end_utc == datetime(2026, 7, 1, 5, 0, tzinfo=UTC)
        assert window.start_local.isoformat() == "2026-06-01"
        assert window.end_local.isoformat() == "2026-07-01"
        assert window.as_of_date.isoformat() == "2026-06-30"
        assert window.period_slug == "2026-06"
        assert window.label == "2026-06"

    def test_march_dst_start_crosses_the_spring_forward(self) -> None:
        # DST begins Sun Mar 8 2026: the 1st is CST (UTC-6), Apr 1 is CDT (UTC-5).
        window = _service()._compute_window(_CHICAGO, ReportMonth(2026, 3))
        assert window.start_utc == datetime(2026, 3, 1, 6, 0, tzinfo=UTC)
        assert window.end_utc == datetime(2026, 4, 1, 5, 0, tzinfo=UTC)
        assert window.as_of_date.isoformat() == "2026-03-31"

    def test_november_dst_end_crosses_the_fall_back(self) -> None:
        # DST ends Sun Nov 1 2026 at 2am: midnight Nov 1 is still CDT (UTC-5),
        # Dec 1 is CST (UTC-6).
        window = _service()._compute_window(_CHICAGO, ReportMonth(2026, 11))
        assert window.start_utc == datetime(2026, 11, 1, 5, 0, tzinfo=UTC)
        assert window.end_utc == datetime(2026, 12, 1, 6, 0, tzinfo=UTC)
        assert window.as_of_date.isoformat() == "2026-11-30"


class TestToDollars:
    """Cents -> 2-decimal dollar amounts at the CSV boundary."""

    def test_conversions(self) -> None:
        to_dollars = ReportsPeriodService._to_dollars
        assert to_dollars(0) == Decimal("0.00")
        assert to_dollars(1) == Decimal("0.01")
        assert to_dollars(99) == Decimal("0.99")
        assert to_dollars(100) == Decimal("1.00")
        assert to_dollars(12345) == Decimal("123.45")
        # Refunds are stored negative and stay negative dollars.
        assert to_dollars(-500) == Decimal("-5.00")

    def test_result_is_always_two_decimals(self) -> None:
        assert str(ReportsPeriodService._to_dollars(100)) == "1.00"
        assert str(ReportsPeriodService._to_dollars(150)) == "1.50"
