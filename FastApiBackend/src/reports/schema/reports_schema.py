"""Schemas for the reports domain.

The only structured input either endpoint takes is the optional report month
(``?month=YYYY-MM``). ``ReportMonth`` parses + validates it; an omitted month
means "all-time". Both zip endpoints return raw bytes (``application/zip``),
not a Pydantic response model, so there is no response schema here.
"""

import re
from dataclasses import dataclass
from enum import StrEnum

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
                month in ``01``..``12``.
        """
        match = _MONTH_PATTERN.match(raw.strip())
        if match is None:
            raise ValueError("month must be in YYYY-MM format")
        year = int(match.group(1))
        month = int(match.group(2))
        if not 1 <= month <= 12:
            raise ValueError("month must be between 01 and 12")
        return cls(year=year, month=month)
