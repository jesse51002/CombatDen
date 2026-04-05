"""Service for computing weekly class attendance streaks."""

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


def _current_week_monday() -> date:
    """Return the Monday of the current ISO week (UTC).

    Returns:
        A date representing Monday of this week.
    """
    today = datetime.now(UTC).date()
    return today - timedelta(days=today.weekday())


class ClassesStreakService:
    """Computes the weekly class attendance streak for a member.

    A week counts toward the streak if the member attended at
    least one class. The current (incomplete) week is included
    if the member has already attended. If they haven't attended
    this week yet, the streak is measured from last week back
    so they aren't penalised mid-week.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_streak(
        self,
        crm_user_id: UUID,
        gym_id: UUID,
    ) -> int:
        """Calculate the current weekly attendance streak.

        Args:
            crm_user_id: The member to check.
            gym_id: The gym to check.

        Returns:
            Number of consecutive weeks with at least one class.
        """
        sql = load_sql(SQL_DIR / "classes_streak.sql")
        params = {
            "crm_user_id": str(crm_user_id),
            "gym_id": str(gym_id),
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = result.all()

        if not rows:
            return 0

        week_starts: set[date] = {row[0] for row in rows}
        return self._count_streak(week_starts)

    @staticmethod
    def _count_streak(week_starts: set[date]) -> int:
        """Walk backwards from now through consecutive attended weeks.

        If neither the current week nor the previous week has
        attendance, the streak is 0 regardless of older data.

        Args:
            week_starts: Set of Monday dates from the DB.

        Returns:
            The streak length in weeks.
        """
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
