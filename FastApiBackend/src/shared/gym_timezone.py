"""Utilities for a gym's timezone — date math + the shared timezone lookup."""

from datetime import UTC, date, datetime
from pathlib import Path
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql

_SQL_DIR = Path(__file__).parent / "sql"


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


async def get_gym_timezone(session: AsyncSession, gym_id: UUID) -> str:
    """Fetch a gym's IANA timezone within the caller's transaction.

    The shared lookup so any service can read a gym's timezone (e.g. to convert
    Stripe period timestamps to gym-local dates) without redefining the query.
    Reads the gyms table (service-role).
    """
    sql = load_sql(_SQL_DIR / "gym_timezone_by_id.sql")
    result = await session.execute(text(sql), {"gym_id": str(gym_id)})
    return result.scalar_one()
