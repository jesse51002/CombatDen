"""Service for computing weekly class attendance streaks."""

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


def _current_week_monday() -> date:
    today = datetime.now(UTC).date()
    return today - timedelta(days=today.weekday())


class ClassesStreakService:
    """Counts consecutive weeks with at least one class attendance.

    The current incomplete week counts toward the streak only if the
    member has already attended this week. Otherwise the streak is
    measured from last week back so members aren't penalised mid-week.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_streak(self, member_id: UUID, gym_id: UUID) -> int:
        """Calculate the current weekly attendance streak."""
        sql = load_sql(SQL_DIR / "streak_weeks.sql")
        params = {
            "member_id": str(member_id),
            "gym_id": str(gym_id),
        }

        async with self._db_pool.session() as session:
            rows = (await session.execute(text(sql), params)).all()

        week_starts: set[date] = {row[0] for row in rows}
        return self._count_streak(week_starts)

    @staticmethod
    def _count_streak(week_starts: set[date]) -> int:
        current_monday = _current_week_monday()
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
