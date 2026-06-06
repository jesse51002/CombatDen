"""Unit tests for gym-timezone date conversion (pure, no DB).

The billing engine stores ``next_due_date`` / ``start_date`` / ``end_date`` as
**gym-local** calendar dates. Stripe period anchors are unix timestamps, so
reading them back must use the gym's timezone — a naive UTC date lands a day
early for gyms east of UTC and a day late for those far west. These lock that.
"""

from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

import src.shared.db_schema_path  # noqa: F401
from src.shared.gym_timezone import stripe_ts_to_gym_date


def test_midnight_jst_resolves_to_jst_date_not_utc_previous() -> None:
    """Midnight in Tokyo (UTC+9) is the previous day in UTC — the gym-local
    conversion must return the Tokyo date, not the UTC date."""
    tokyo = ZoneInfo("Asia/Tokyo")
    midnight_jst = datetime(2026, 6, 6, 0, 0, tzinfo=tokyo)
    ts = int(midnight_jst.timestamp())

    # Sanity: that same instant is the *previous* calendar day in UTC.
    assert datetime.fromtimestamp(ts, UTC).date() == date(2026, 6, 5)
    # The gym-local (Tokyo) conversion gives the correct day.
    assert stripe_ts_to_gym_date(ts, "Asia/Tokyo") == date(2026, 6, 6)


def test_early_utc_morning_resolves_to_previous_day_in_chicago() -> None:
    """An instant just after UTC midnight is still the previous day in Chicago
    (UTC-5 in June) — the conversion must shift it back, not forward."""
    instant = datetime(2026, 6, 6, 2, 0, tzinfo=UTC)
    ts = int(instant.timestamp())

    assert instant.date() == date(2026, 6, 6)
    assert stripe_ts_to_gym_date(ts, "America/Chicago") == date(2026, 6, 5)
