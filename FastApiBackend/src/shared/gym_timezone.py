"""Utility for computing the current date in a gym's timezone."""

from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo


def gym_today(tz_name: str) -> date:
    """Return today's date in the specified timezone.

    Args:
        tz_name: IANA timezone name (e.g., 'America/Chicago').

    Returns:
        The current date in the given timezone.
    """
    return datetime.now(UTC).astimezone(ZoneInfo(tz_name)).date()
