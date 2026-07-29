"""Live-DB proof of the profile's current-week strip.

``BillingRetention.current_week_attended_weekdays`` is what a rank-disabled
gym's profile screen renders as its centrepiece: the weekdays of THIS week the
member trained, SUNDAY-FIRST (0 = Sunday .. 6 = Saturday), served on the same
payload as ``class_streak_weeks`` so the screen needs one call, not two.

Two properties have to hold or the strip lies:

1. **The week is GYM-LOCAL.** A class late on the gym-local last day of the week
   belongs to THIS week; the same wall-clock instant read in UTC would spill
   into the next one. The fixture gym sits in ``Pacific/Kiritimati`` (UTC+14) so
   every gym-local day differs from the UTC day for part of the clock — a UTC
   bucketing fails these tests instead of passing by luck in a US timezone.
2. **The strip counts what the STREAK counts.** Both come from
   ``StreakService.get_streak_details`` — one session, one gym-local Monday
   anchor — so the dots and the number beside them can never contradict.

Attendance rows are written directly (a real check-in would need memberships,
plans and Stripe); the read path under test is the real service.

Prereqs: the local Supabase stack is up. No backend process, no Stripe.
"""

from collections.abc import AsyncGenerator
from datetime import date, datetime, time, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy import text

from src.checkin.service.streak_service import StreakService

# UTC+14, the furthest-ahead civil timezone: a gym-local evening is already the
# NEXT day in UTC, so any read that forgets to convert lands on the wrong day.
GYM_TZ = "Pacific/Kiritimati"


@pytest.fixture
async def strip_gym(db_pool) -> AsyncGenerator[dict]:
    """A throwaway gym (UTC+14) with one member and one class.

    Teardown removes exactly what it inserts, newest FK first.
    """
    async with db_pool.session() as session:
        gym = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gyms (gym_name, timezone) "
                            "VALUES (:name, :tz) RETURNING gym_id"
                        ),
                        {
                            "name": f"ZZ Strip Gym {uuid4().hex[:8]}",
                            "tz": GYM_TZ,
                        },
                    )
                ).mappings().fetchone()["gym_id"]
            )
        )
        member = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO members (gym_id, first_name, "
                            "last_name, email) VALUES (:g, 'ZZ', 'Strip', :e) "
                            "RETURNING member_id"
                        ),
                        {
                            "g": str(gym),
                            "e": f"zz-strip-{uuid4().hex[:10]}@example.com",
                        },
                    )
                ).mappings().fetchone()["member_id"]
            )
        )
        klass = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gym_classes (gym_id, class_name, "
                            "image_url) VALUES (:g, 'ZZ Strip Class', "
                            "'https://x/c.png') RETURNING class_id"
                        ),
                        {"g": str(gym)},
                    )
                ).mappings().fetchone()["class_id"]
            )
        )
        await session.commit()

    try:
        yield {"gym_id": gym, "member_id": member, "class_id": klass}
    finally:
        async with db_pool.session() as session:
            for stmt in (
                "DELETE FROM member_attendance WHERE gym_id = :g",
                "DELETE FROM gym_classes WHERE gym_id = :g",
                "DELETE FROM members WHERE gym_id = :g",
                "DELETE FROM gyms WHERE gym_id = :g",
            ):
                await session.execute(text(stmt), {"g": str(gym)})
            await session.commit()


def _gym_today() -> date:
    """Today in the fixture gym's timezone — the anchor the service uses."""
    return datetime.now(ZoneInfo(GYM_TZ)).date()


def _gym_week_monday() -> date:
    today = _gym_today()
    return today - timedelta(days=today.weekday())


async def _attend(db_pool, ctx: dict, local_day: date, local_time: time) -> None:
    """Record attendance at a gym-local wall-clock instant.

    ``occurred_at`` is a timestamptz, so the gym-local wall clock is converted
    to the real instant here — exactly what a check-in stores. That is what
    makes the UTC+14 boundary cases meaningful.
    """
    occurred_at = datetime.combine(
        local_day, local_time, tzinfo=ZoneInfo(GYM_TZ)
    )
    async with db_pool.session() as session:
        await session.execute(
            text(
                "INSERT INTO member_attendance (member_id, gym_id, class_id, "
                "original_date, original_time, occurred_at) "
                "VALUES (:m, :g, :c, :d, :t, :ts)"
            ),
            {
                "m": str(ctx["member_id"]),
                "g": str(ctx["gym_id"]),
                "c": str(ctx["class_id"]),
                "d": local_day,
                "t": local_time,
                "ts": occurred_at,
            },
        )
        await session.commit()


async def _strip(db_pool, ctx: dict) -> list[int]:
    """The Sunday-first strip exactly as the profile payload carries it."""
    service = StreakService(db_pool=db_pool)
    result = await service.get_streak_details(ctx["member_id"], ctx["gym_id"])
    return StreakService.sunday_first_attended_indices(result.current_week_days)


# ── the strip ─────────────────────────────────────────────────────


async def test_no_classes_this_week_is_an_empty_strip(
    db_pool, strip_gym
) -> None:
    """A member who has not trained gets ``[]`` — a valid, empty state."""
    assert await _strip(db_pool, strip_gym) == []


async def test_monday_and_wednesday_return_exactly_those_indices(
    db_pool, strip_gym
) -> None:
    """Mon + Wed → ``[1, 3]`` on the SUNDAY-FIRST strip the client renders.

    Sunday-first is the origin of the member app's ``StreakWeekStrip`` /
    ``completedWeekdayIndices()``; a Monday-first list would mark Sunday and
    Tuesday instead — silently, and only ever noticed by a member.
    """
    monday = _gym_week_monday()
    await _attend(db_pool, strip_gym, monday, time(18, 0))
    await _attend(db_pool, strip_gym, monday + timedelta(days=2), time(19, 30))

    assert await _strip(db_pool, strip_gym) == [1, 3]


async def test_last_weeks_class_is_excluded(db_pool, strip_gym) -> None:
    """A class in the PREVIOUS gym-local week never lights this week's dot."""
    monday = _gym_week_monday()
    await _attend(db_pool, strip_gym, monday - timedelta(days=3), time(18, 0))

    assert await _strip(db_pool, strip_gym) == []

    # ...and the same weekday THIS week does light it, so the exclusion is the
    # week window, not a broken query.
    await _attend(db_pool, strip_gym, monday + timedelta(days=4), time(18, 0))
    assert await _strip(db_pool, strip_gym) == [5]


async def test_late_class_on_the_weeks_last_gym_local_day_stays_in_the_week(
    db_pool, strip_gym
) -> None:
    """23:30 on the gym-local SUNDAY is still this week — the UTC trap.

    The gym runs at UTC+14, so 23:30 Sunday gym-local is already Sunday 09:30
    UTC — but 00:30 Monday gym-local is Sunday 10:30 UTC, i.e. the UTC day
    does not move where the gym-local day does. Bucketing on the raw
    ``occurred_at`` instead of ``occurred_at AT TIME ZONE gyms.timezone``
    misplaces both of these.
    """
    monday = _gym_week_monday()
    sunday = monday + timedelta(days=6)
    await _attend(db_pool, strip_gym, sunday, time(23, 30))

    # Sunday is index 0 on a Sunday-first strip — the LAST day of the streak's
    # Monday-start week, rendered in the strip's first cell (see
    # BillingRetention.current_week_attended_weekdays).
    assert await _strip(db_pool, strip_gym) == [0]


async def test_earliest_class_on_the_weeks_first_gym_local_day_is_included(
    db_pool, strip_gym
) -> None:
    """00:00 on the gym-local MONDAY opens the week, not closes the last one."""
    monday = _gym_week_monday()
    await _attend(db_pool, strip_gym, monday, time(0, 0))

    assert await _strip(db_pool, strip_gym) == [1]


async def test_strip_and_streak_count_agree_on_the_same_week(
    db_pool, strip_gym
) -> None:
    """One call, one anchor: a non-empty strip implies the streak counts it.

    They are rendered side by side, so "trained Tuesday" and "0-week streak"
    must never appear together.
    """
    service = StreakService(db_pool=db_pool)
    monday = _gym_week_monday()
    await _attend(db_pool, strip_gym, monday + timedelta(days=1), time(7, 0))

    result = await service.get_streak_details(
        strip_gym["member_id"], strip_gym["gym_id"]
    )

    assert StreakService.sunday_first_attended_indices(
        result.current_week_days
    ) == [2]
    assert result.weeks >= 1


# ── the re-indexing itself (hermetic) ─────────────────────────────


@pytest.mark.parametrize(
    ("monday_first", "expected"),
    [
        ([False] * 7, []),
        # index 0 is Monday on the input, which is index 1 Sunday-first.
        ([True, False, False, False, False, False, False], [1]),
        # index 6 is Sunday on the input, which folds to index 0.
        ([False, False, False, False, False, False, True], [0]),
        ([True, False, True, False, False, False, True], [0, 1, 3]),
        ([True] * 7, [0, 1, 2, 3, 4, 5, 6]),
    ],
)
def test_sunday_first_reindex(
    monday_first: list[bool], expected: list[int]
) -> None:
    """Monday-first booleans → ascending Sunday-first indices."""
    assert (
        StreakService.sunday_first_attended_indices(monday_first) == expected
    )
