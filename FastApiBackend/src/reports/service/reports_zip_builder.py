"""In-memory CSV-into-zip builder for the reports domain.

A ``ReportsZipBuilder`` is a PER-REQUEST instance (never a DI singleton): each
endpoint call constructs one, adds each CSV, and reads the finished zip bytes.
It owns two cross-cutting concerns every report/export CSV needs:

- **utf-8-sig encoding** — every CSV is written with a BOM so Excel opens
  non-ASCII cells (member names, accented text) in the right encoding.
- **CSV-injection defense** — a TEXT cell that begins with a formula-trigger
  character (``= + - @`` tab CR) is prefixed with a single apostrophe so a
  spreadsheet renders it as text instead of executing it. NUMERIC cells
  (``int`` / ``float`` / ``Decimal``) are emitted as plain numbers and are
  NEVER escaped — a negative dollar amount like ``-5.00`` must stay a number,
  while the text ``-cmd`` must be neutralised.
"""

import csv
import io
import zipfile
from datetime import date, datetime, time
from decimal import Decimal
from uuid import UUID

# Leading characters a spreadsheet may interpret as the start of a formula.
# A TEXT cell starting with one of these is prefixed with an apostrophe.
_FORMULA_TRIGGERS = frozenset({"=", "+", "-", "@", "\t", "\r"})

# A cell value that is safe to render verbatim (never a formula trigger) and
# formatted deterministically rather than run through the text-escape path.
type CsvCell = str | int | float | Decimal | bool | datetime | date | time | UUID | None


class ReportsZipBuilder:
    """Accumulates named CSV files into one in-memory ZIP archive."""

    def __init__(self) -> None:
        self._buffer = io.BytesIO()
        self._zip = zipfile.ZipFile(
            self._buffer, "w", zipfile.ZIP_DEFLATED
        )
        self._finished = False

    def add_csv(
        self,
        name: str,
        header: tuple[str, ...],
        rows: list[tuple[CsvCell, ...]],
    ) -> None:
        """Write one CSV file into the archive.

        Args:
            name: The file name inside the zip (e.g. ``"payments.csv"``).
            header: The column header row (our own trusted identifiers).
            rows: The data rows; each cell is formatted + injection-guarded.
        """
        text_buffer = io.StringIO()
        writer = csv.writer(text_buffer)
        writer.writerow(header)
        for row in rows:
            writer.writerow([self._format_cell(cell) for cell in row])
        # utf-8-sig writes the BOM Excel needs to detect the encoding.
        self._zip.writestr(name, text_buffer.getvalue().encode("utf-8-sig"))

    def finish(self) -> bytes:
        """Close the archive and return its bytes (idempotent)."""
        if not self._finished:
            self._zip.close()
            self._finished = True
        return self._buffer.getvalue()

    def _format_cell(self, value: CsvCell) -> str:
        """Format one cell to its final CSV string, escaping only text.

        Numeric / boolean / temporal / UUID values are rendered
        deterministically and are never treated as formulas. Genuine strings
        are the only cells that can carry a leading formula trigger, so only
        they get the apostrophe defense.
        """
        if value is None:
            return ""
        if isinstance(value, bool):
            # bool is an int subclass — handle it before the numeric branch.
            return "true" if value else "false"
        if isinstance(value, (int, float, Decimal)):
            return str(value)
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, (date, time)):
            return value.isoformat()
        if isinstance(value, UUID):
            return str(value)
        return self._escape_text(str(value))

    @staticmethod
    def _escape_text(text: str) -> str:
        """Prefix a leading formula trigger with an apostrophe (else verbatim)."""
        if text and text[0] in _FORMULA_TRIGGERS:
            return "'" + text
        return text
