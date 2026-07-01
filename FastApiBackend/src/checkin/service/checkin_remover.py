"""Remove one member's check-in from a class occurrence (reverse the award).

A thin occurrence-finding wrapper over the shared per-member reverser
(``CheckinReverser``): resolve the materialized ``class_history`` row for the
gym-local calendar day, then delegate the actual reversal — delete the member's
attendance, claw back the awarded points (clamped at 0), remove a
``class_attended`` activity, and reverse the auto-end on the charged pack when
the removal drops it back below capacity — to the reverser for this one member.
The occurrence (``class_history``) itself is left intact: the class still
happened, this one member just didn't attend.

One-way ``checkin -> classes`` dependency: the occurrence resolution here (the
gym timezone + the gym-local day-bounds ``class_history`` lookup) reuses the
classes SQL (loaded from ``CLASSES_SQL_DIR``), exactly as the writer reuses the
classes timezone SQL. The reversal core itself (``CheckinReverser``) imports
nothing from ``src.classes``.
"""

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import CheckinRemoveResponse
from src.checkin.service.checkin_reverser import CheckinReverser
from src.classes import SQL_DIR as CLASSES_SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_FALLBACK_TIMEZONE = "America/Chicago"


class CheckinRemover:
    """Reverses a single member's check-in on one occurrence.

    Args:
        db_pool: Injected database connection pool.
        reverser: The shared per-member reversal core (delete attendance + claw
            back points + drop activity + reverse the pack auto-end).
    """

    def __init__(
        self, db_pool: DirectDatabasePool, reverser: CheckinReverser
    ) -> None:
        self._db_pool = db_pool
        self._reverser = reverser

    async def remove(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        member_id: UUID,
    ) -> CheckinRemoveResponse:
        """Delete the member's attendance + reverse its points / pack / activity.

        Returns a ``removed=False`` result (no error) when the member was not
        checked in, or the occurrence was never materialized.

        Raises:
            ValueError: If the class does not exist for this gym (mapped to 404).
        """
        async with self._db_pool.session() as session:
            class_row = await self._load_class(session, class_id, gym_id)
            points_worth = int(class_row["points_worth"])

            history_id = await self._find_history(
                session, class_id, gym_id, occurrence_date
            )
            if history_id is None:
                return CheckinRemoveResponse(removed=False)

            result = await self._reverser.reverse(
                session,
                history_id,
                member_id,
                gym_id,
                class_id,
                points_worth,
            )
            await session.commit()

        return result

    # -- occurrence resolution -------------------------------------------

    async def _load_class(
        self, session: AsyncSession, class_id: UUID, gym_id: UUID
    ) -> dict:
        """Load the class (gym auth + points_worth); 404 on a wrong/absent gym."""
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_load_class_for_removal.sql"),
            {"class_id": str(class_id)},
        )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return row

    async def _find_history(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> UUID | None:
        """The materialized history row for the gym-local day, or None.

        Matches the whole local day in UTC (gym-local midnight to the next), so a
        per-occurrence time override still resolves to the same row. None means
        the occurrence was never materialized (nobody is checked in).
        """
        zone = ZoneInfo(await self._gym_timezone(session, gym_id))
        day_start = datetime.combine(
            occurrence_date, time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        day_end = datetime.combine(
            occurrence_date + timedelta(days=1), time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        row = await self._fetchone(
            session,
            load_sql(CLASSES_SQL_DIR / "classes_undo_find_history.sql"),
            {"class_id": str(class_id), "start": day_start, "end": day_end},
        )
        return row["class_history_id"] if row else None

    async def _gym_timezone(
        self, session: AsyncSession, gym_id: UUID
    ) -> str:
        """The gym's IANA timezone (fallback to America/Chicago)."""
        row = await self._fetchone(
            session,
            load_sql(CLASSES_SQL_DIR / "get_gym_timezone.sql"),
            {"gym_id": str(gym_id)},
        )
        return row["timezone"] if row else _FALLBACK_TIMEZONE

    @staticmethod
    async def _fetchone(
        session: AsyncSession, sql: str, params: dict
    ) -> dict | None:
        """One row of a query as a dict, or None."""
        row = (
            (await session.execute(text(sql), params)).mappings().fetchone()
        )
        return dict(row) if row else None
