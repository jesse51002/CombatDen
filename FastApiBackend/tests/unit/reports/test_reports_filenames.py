"""Unit tests for the filename slug contract + the month validator."""

from uuid import UUID

import pytest

from src.reports.schema.reports_schema import ReportMembershipChange, ReportMonth
from src.reports.service.reports_filenames import (
    full_export_filename,
    gym_slug,
    report_filename,
)

_GYM_ID = UUID("21636369-8b52-9b4a-97b7-50923ceb3ffd")


class TestGymSlug:
    """Lowercase, non-alnum runs -> dash, trimmed, id fallback when empty."""

    def test_basic_slug(self) -> None:
        assert gym_slug("Iron Fist Gym", _GYM_ID) == "iron-fist-gym"

    def test_collapses_runs_and_trims(self) -> None:
        assert gym_slug("  Iron & Fist!!  ", _GYM_ID) == "iron-fist"

    def test_non_ascii_is_dropped(self) -> None:
        assert gym_slug("Café 42", _GYM_ID) == "caf-42"

    def test_empty_after_stripping_falls_back_to_id(self) -> None:
        assert gym_slug("!!!", _GYM_ID) == f"gym-{_GYM_ID.hex[:8]}"
        assert gym_slug("   ", _GYM_ID) == f"gym-{_GYM_ID.hex[:8]}"


class TestFilenames:
    """The report + export download names."""

    def test_report_filename_month(self) -> None:
        assert (
            report_filename("Iron Fist", _GYM_ID, "2026-06")
            == "combatden_report_iron-fist_2026-06.zip"
        )

    def test_report_filename_all_time(self) -> None:
        assert (
            report_filename("Iron Fist", _GYM_ID, "all-time")
            == "combatden_report_iron-fist_all-time.zip"
        )

    def test_full_export_filename(self) -> None:
        # YYYYMMDD, no dashes, combatden_ prefix.
        assert (
            full_export_filename("Iron Fist", _GYM_ID, "20260630")
            == "combatden_export_iron-fist_20260630.zip"
        )


class TestReportMonthParse:
    """The YYYY-MM validator behind the endpoint's 400."""

    def test_valid_month(self) -> None:
        parsed = ReportMonth.parse("2026-06")
        assert parsed == ReportMonth(2026, 6)

    def test_leading_and_trailing_whitespace_is_tolerated(self) -> None:
        assert ReportMonth.parse("  2026-06 ") == ReportMonth(2026, 6)

    @pytest.mark.parametrize(
        "bad",
        ["2026-13", "2026-00", "2026-6", "not-a-month", "2026-06-01", "", "202606"],
    )
    def test_invalid_month_raises(self, bad: str) -> None:
        with pytest.raises(ValueError):
            ReportMonth.parse(bad)


class TestReportMembershipChange:
    """The report-internal change-type enum mirrors the SQL literals."""

    def test_values(self) -> None:
        assert ReportMembershipChange.started == "started"
        assert ReportMembershipChange.cancelled == "cancelled"
        assert ReportMembershipChange.ended == "ended"
