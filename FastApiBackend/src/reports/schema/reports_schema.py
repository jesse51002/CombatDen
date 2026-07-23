"""Schemas for the reports domain.

The only structured input either endpoint takes is the optional report month
(``?month=YYYY-MM``). ``ReportMonth`` parses + validates it; an omitted month
means "all-time". Both zip endpoints return raw bytes (``application/zip``),
not a Pydantic response model, so there is no response schema here.
"""

import re
from dataclasses import dataclass
from datetime import date
from enum import StrEnum

from dateutil.relativedelta import relativedelta

# A report month is exactly ``YYYY-MM`` (zero-padded). Anything else is a 400.
_MONTH_PATTERN = re.compile(r"^(\d{4})-(\d{2})$")


class ReportMembershipChange(StrEnum):
    """A membership lifecycle event in the report's membership_changes sheet.

    Report-internal (not a Postgres enum): the ``change_type`` literals the
    membership-changes query emits (``'started'`` / ``'cancelled'`` /
    ``'ended'``) mirror these values, and the summary counts group by them.
    """

    started = "started"
    cancelled = "cancelled"
    ended = "ended"


@dataclass(frozen=True)
class ReportMonth:
    """A validated calendar-month selector for the period report."""

    year: int
    month: int

    @classmethod
    def parse(cls, raw: str) -> "ReportMonth":
        """Parse a ``YYYY-MM`` string into a ``ReportMonth``.

        Args:
            raw: The raw ``month`` query value.

        Returns:
            The parsed month.

        Raises:
            ValueError: If the string is not a well-formed ``YYYY-MM`` with a
                month in ``01``..``12``, or names a year whose month window
                falls outside the supported calendar range.
        """
        match = _MONTH_PATTERN.match(raw.strip())
        if match is None:
            raise ValueError("month must be in YYYY-MM format")
        year = int(match.group(1))
        month = int(match.group(2))
        if not 1 <= month <= 12:
            raise ValueError("month must be between 01 and 12")
        # Reject a year whose month window can't be constructed (e.g. 0000 or
        # 9999-12): the period service builds ``date(year, month, 1)`` and adds
        # a month for the window's exclusive end, both of which raise on an
        # out-of-range year. Validating that construction here keeps malformed
        # input a 400 at the boundary instead of a 500 deep in the service.
        try:
            date(year, month, 1) + relativedelta(months=1)
        except (ValueError, OverflowError) as exc:
            raise ValueError(
                "month is outside the supported calendar range"
            ) from exc
        return cls(year=year, month=month)
