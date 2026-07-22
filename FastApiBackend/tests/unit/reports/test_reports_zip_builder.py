"""Unit tests for ReportsZipBuilder — round-trip, encoding, and CSV-injection.

Pure, no DB or network. Verifies the zip opens, every CSV carries the
utf-8-sig BOM, formula-trigger TEXT cells are apostrophe-escaped, and numeric
cells (including negative dollar amounts) are emitted as plain numbers.
"""

import csv
import io
import zipfile
from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import UUID

from src.reports.service.reports_zip_builder import ReportsZipBuilder

_BOM = b"\xef\xbb\xbf"


class TestRoundTrip:
    """The archive opens and its CSVs parse back to the written values."""

    def test_zip_opens_and_lists_the_files(self) -> None:
        builder = ReportsZipBuilder()
        builder.add_csv("a.csv", ("x",), [("1",)])
        builder.add_csv("b.csv", ("y",), [("2",)])
        data = builder.finish()

        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            assert set(zf.namelist()) == {"a.csv", "b.csv"}

    def test_every_csv_starts_with_the_utf8_sig_bom(self) -> None:
        builder = ReportsZipBuilder()
        builder.add_csv("m.csv", ("name",), [("Café",)])
        data = builder.finish()

        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            raw = zf.read("m.csv")
        assert raw.startswith(_BOM)
        # And the BOM-aware decode recovers the non-ASCII value.
        text = raw.decode("utf-8-sig")
        assert "Café" in text

    def test_finish_is_idempotent(self) -> None:
        builder = ReportsZipBuilder()
        builder.add_csv("a.csv", ("x",), [("1",)])
        first = builder.finish()
        second = builder.finish()
        assert first == second

    def test_mixed_types_round_trip(self) -> None:
        member_id = UUID("21636369-8b52-9b4a-97b7-50923ceb3ffd")
        builder = ReportsZipBuilder()
        builder.add_csv(
            "rows.csv",
            ("id", "amount", "when", "day", "clock", "flag", "empty"),
            [
                (
                    member_id,
                    Decimal("12.50"),
                    datetime(2026, 6, 1, 9, 30, tzinfo=UTC),
                    date(2026, 6, 1),
                    time(9, 30),
                    True,
                    None,
                )
            ],
        )
        data = builder.finish()

        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            text = zf.read("rows.csv").decode("utf-8-sig")
        reader = list(csv.reader(io.StringIO(text)))
        assert reader[0] == [
            "id", "amount", "when", "day", "clock", "flag", "empty",
        ]
        assert reader[1] == [
            str(member_id),
            "12.50",
            "2026-06-01T09:30:00+00:00",
            "2026-06-01",
            "09:30:00",
            "true",
            "",
        ]


class TestFormulaEscape:
    """TEXT cells with a leading trigger get an apostrophe; numbers do not."""

    def test_text_triggers_are_escaped(self) -> None:
        builder = ReportsZipBuilder()
        assert builder._format_cell("=SUM(A1)") == "'=SUM(A1)"
        assert builder._format_cell("+cmd") == "'+cmd"
        assert builder._format_cell("-danger") == "'-danger"
        assert builder._format_cell("@ref") == "'@ref"
        assert builder._format_cell("\ttab") == "'\ttab"
        assert builder._format_cell("\rcr") == "'\rcr"

    def test_numeric_cells_are_never_escaped(self) -> None:
        builder = ReportsZipBuilder()
        # A negative dollar refund is a NUMBER, not a formula.
        assert builder._format_cell(Decimal("-5.00")) == "-5.00"
        assert builder._format_cell(-5) == "-5"
        assert builder._format_cell(3.5) == "3.5"
        assert builder._format_cell(0) == "0"

    def test_safe_text_and_none_pass_through(self) -> None:
        builder = ReportsZipBuilder()
        assert builder._format_cell("normal name") == "normal name"
        assert builder._format_cell("") == ""
        assert builder._format_cell(None) == ""

    def test_bool_renders_lowercase(self) -> None:
        builder = ReportsZipBuilder()
        assert builder._format_cell(True) == "true"
        assert builder._format_cell(False) == "false"

    def test_escape_survives_the_round_trip(self) -> None:
        builder = ReportsZipBuilder()
        builder.add_csv(
            "danger.csv",
            ("cell", "amount"),
            [("=1+1", Decimal("-5.00"))],
        )
        data = builder.finish()
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            text = zf.read("danger.csv").decode("utf-8-sig")
        row = list(csv.reader(io.StringIO(text)))[1]
        assert row[0] == "'=1+1"
        assert row[1] == "-5.00"
