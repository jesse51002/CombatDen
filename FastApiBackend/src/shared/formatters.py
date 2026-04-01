"""Shared formatting utilities for display strings.

Provides reusable helpers for dates, durations, prices,
and relative time formatting used across domain services.
"""

from datetime import UTC, date, datetime

DURATION_UNIT_LABELS = {
    "week": "week",
    "month": "month",
    "year": "year",
}


def format_date(d: date | None) -> str:
    """Format a date as 'Jan, 18. 2025'.

    Args:
        d: Date to format.

    Returns:
        Formatted date string or 'N/A' if None.
    """
    if not d:
        return "N/A"
    return f"{d.strftime('%b')}, {d.day:02d}. {d.year}"


def format_duration(days: int) -> str:
    """Format a duration as 'X days' or 'X months'.

    Args:
        days: Number of days.

    Returns:
        Formatted duration string.
    """
    if days < 0:
        days = 0
    if days < 30:
        return f"{days} day{'s' if days != 1 else ''}"
    months = days // 30
    return f"{months} month{'s' if months != 1 else ''}"


def format_price(amount: float, duration_unit: str) -> str:
    """Format a price as '$165/month'.

    Args:
        amount: Dollar amount.
        duration_unit: Billing cycle unit.

    Returns:
        Formatted price string.
    """
    amount_str = f"${int(amount)}" if amount == int(amount) else f"${amount:.2f}"
    label = DURATION_UNIT_LABELS.get(duration_unit, duration_unit)
    return f"{amount_str}/{label}"


def format_time_ago(dt: datetime) -> str:
    """Format a datetime as a relative time-ago string.

    Args:
        dt: The datetime to format.

    Returns:
        String like '3 days ago' or 'just now'.
    """
    now = datetime.now(UTC)
    delta = now - dt
    days = delta.days

    if days == 0:
        hours = delta.seconds // 3600
        if hours == 0:
            return "just now"
        return f"{hours} hour{'s' if hours != 1 else ''} ago"
    if days == 1:
        return "1 day ago"
    return f"{days} days ago"


def format_duration_since(dt: datetime | None) -> str:
    """Format duration from a datetime to now.

    Args:
        dt: Start datetime.

    Returns:
        String like '18 days' or '3 months'.
    """
    if not dt:
        return "N/A"
    now = datetime.now(UTC)
    delta = now - dt
    return format_duration(delta.days)
