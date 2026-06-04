"""Shared time helpers for Stripe webhook handlers."""

from datetime import UTC, date, datetime


def stripe_ts_to_datetime(ts: int | None) -> datetime | None:
    """Convert a Stripe Unix timestamp (seconds) to a UTC datetime."""
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, tz=UTC)


def stripe_ts_to_date(ts: int | None) -> date | None:
    """Convert a Stripe Unix timestamp (seconds) to a UTC date."""
    dt = stripe_ts_to_datetime(ts)
    return dt.date() if dt is not None else None
