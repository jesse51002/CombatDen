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


def stripe_ts_to_gym_date(ts: int, tz_name: str) -> date:
    """Return the date of a Stripe unix timestamp in the gym's timezone.

    Stripe billing anchors are pinned to midnight in the gym's timezone, so a
    period-end (the next due date) must be read back in that timezone — a UTC
    date would land a day early for gyms east of UTC. Keeps next_due_date
    consistent with ``start_date`` / ``end_date``, which are gym-local.

    Args:
        ts: Stripe Unix timestamp in seconds (e.g. ``current_period_end``).
        tz_name: IANA timezone name (e.g., 'America/Chicago').

    Returns:
        The calendar date of that instant in the given timezone.
    """
    return datetime.fromtimestamp(ts, UTC).astimezone(ZoneInfo(tz_name)).date()
