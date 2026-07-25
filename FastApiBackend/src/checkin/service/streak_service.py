"""Service for computing weekly class attendance streaks."""

from collections.abc import Iterable
from datetime import date, timedelta
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import StreakResult
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import get_gym_timezone, gym_today
from src.shared.sql_loader import load_sql


class StreakService:
    """Counts consecutive weeks with at least one class attendance.

    The current incomplete week counts toward the streak only if the
    member has already attended this week. Otherwise the streak is
    measured from last week back so members aren't penalised mid-week.

    Weeks are bucketed in the GYM's current-local timezone -- both the SQL
    week truncation and the "current week" anchor here -- not UTC, so a
    late Sunday-evening class doesn't spill into next week's bucket.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_streak(self, member_id: UUID, gym_id: UUID) -> int:
        """Calculate the current weekly attendance streak (week count only).

        The single-query path: runs ONLY ``streak_weeks.sql`` -- callers that
        don't need the per-day strip (e.g. the member billing-detail read)
        don't pay for it. Callers that also need the strip call
        ``get_streak_details``. Both share ``_count_weeks``, so the week count
        can't drift between the two entry points.
        """
        params = {"member_id": str(member_id), "gym_id": str(gym_id)}
        async with self._db_pool.session() as session:
            timezone = await get_gym_timezone(session, gym_id)
            current_monday = self._current_week_monday(timezone)
            return await self._count_weeks(session, params, current_monday)

    async def get_streak_details(
        self, member_id: UUID, gym_id: UUID
    ) -> StreakResult:
        """Compute the streak week count AND the current-week per-day strip.

        The two-query path (only the check-in routes need it): one session,
        one gym-local Monday anchor shared by the weeks query and the per-day
        query, so the strip and the count agree by construction. Reuses the
        same ``_count_weeks`` as ``get_streak``.
        """
        params = {"member_id": str(member_id), "gym_id": str(gym_id)}
        days_sql = load_sql(SQL_DIR / "current_week_days.sql")

        async with self._db_pool.session() as session:
            timezone = await get_gym_timezone(session, gym_id)
            current_monday = self._current_week_monday(timezone)
            weeks = await self._count_weeks(session, params, current_monday)
            day_rows = (
                await session.execute(
                    text(days_sql),
                    {**params, "current_week_monday": current_monday},
                )
            ).all()

        return StreakResult(
            weeks=weeks,
            current_week_days=self._build_week_days(
                row[0] for row in day_rows
            ),
        )

    async def _count_weeks(
        self,
        session: AsyncSession,
        params: dict[str, str],
        current_monday: date,
    ) -> int:
        """Run the weeks query and count the streak (single-sourced).

        The one streak query both entry points share: ``get_streak`` runs
        ONLY this, ``get_streak_details`` runs this plus the per-day query --
        both against the caller's open session and shared ``current_monday``.
        """
        weeks_sql = load_sql(SQL_DIR / "streak_weeks.sql")
        week_rows = (await session.execute(text(weeks_sql), params)).all()
        week_starts: set[date] = {row[0] for row in week_rows}
        return self._count_streak(week_starts, current_monday)

    def _count_streak(
        self, week_starts: set[date], current_monday: date
    ) -> int:
        previous_monday = current_monday - timedelta(weeks=1)

        if current_monday in week_starts:
            cursor = current_monday
        elif previous_monday in week_starts:
            cursor = previous_monday
        else:
            return 0

        streak = 0
        while cursor in week_starts:
            streak += 1
            cursor -= timedelta(weeks=1)
        return streak

    @staticmethod
    def _build_week_days(iso_dows: Iterable[int]) -> list[bool]:
        """Build the Monday-first 7-bool strip from ISO weekday numbers.

        Each input is a Postgres ``ISODOW`` (1 = Monday .. 7 = Sunday); the
        result is indexed 0 = Monday .. 6 = Sunday, ``True`` where the member
        attended.
        """
        days = [False] * 7
        for iso_dow in iso_dows:
            days[iso_dow - 1] = True
        return days

    def _current_week_monday(self, timezone: str) -> date:
        today = gym_today(timezone)
        return today - timedelta(days=today.weekday())
