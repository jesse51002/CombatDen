"""Shared time helpers for Stripe webhook handlers."""

from datetime import UTC, datetime


def stripe_ts_to_datetime(ts: int | None) -> datetime | None:
    """Convert a Stripe Unix timestamp (seconds) to a UTC datetime."""
    if ts is None:
        return None
    return datetime.fromtimestamp(ts, tz=UTC)
