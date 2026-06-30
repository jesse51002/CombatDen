"""Remove one member's check-in from a class occurrence (reverse the award).

The inverse of the check-in writer, scoped to a single member: delete the
attendance row, claw back the awarded points (clamped at 0), remove a
``class_attended`` activity, and -- UNLIKE the whole-occurrence undo -- reverse
the auto-end on the charged pack when the removal drops it back below capacity.
The occurrence (``class_history``) itself is left intact: the class still
happened, this one member just didn't attend.

One-way ``checkin -> classes`` dependency: the gym-local day bounds, the gym
timezone, and the pack-capacity reversal reuse the classes SQL (loaded from
``CLASSES_SQL_DIR``), exactly as the writer reuses the classes timezone SQL.
"""

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import CheckinRemoveResponse
from src.checkin.service.checkin_writer import CLASS_ATTENDED_ACTIVITY_TYPE
from src.classes import SQL_DIR as CLASSES_SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_FALLBACK_TIMEZONE = "America/Chicago"


class CheckinRemover:
    """Reverses a single member's check-in on one occurrence.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

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

            deleted = await self._delete_attendance(
                session, member_id, history_id
            )
            if deleted is None:
                return CheckinRemoveResponse(removed=False)

            await self._revert_points(session, member_id, gym_id, points_worth)
            await self._delete_activity(session, member_id, gym_id, class_id)
            unended = await self._reverse_auto_end(
                session, member_id, deleted["item_id"]
            )

            await session.commit()

        return CheckinRemoveResponse(
            removed=True,
            points_reverted=points_worth,
            membership_unended=unended,
        )

    # -- steps -----------------------------------------------------------

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

    async def _delete_attendance(
        self, session: AsyncSession, member_id: UUID, history_id: UUID
    ) -> dict | None:
        """Delete the member's attendance row; return its (item_id, plan_id)."""
        return await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_delete_member_attendance.sql"),
            {"member_id": str(member_id), "class_history_id": str(history_id)},
        )

    async def _revert_points(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
        points: int,
    ) -> None:
        """Claw back the awarded points, floored at 0 (the balance CHECK)."""
        await session.execute(
            text(load_sql(SQL_DIR / "checkin_revert_points.sql")),
            {"points": points, "m": str(member_id), "g": str(gym_id)},
        )

    async def _delete_activity(
        self,
        session: AsyncSession,
        member_id: UUID,
        gym_id: UUID,
        class_id: UUID,
    ) -> None:
        """Remove one matching class_attended loyalty-feed row (best effort)."""
        await session.execute(
            text(load_sql(SQL_DIR / "checkin_delete_attended_activity.sql")),
            {
                "m": str(member_id),
                "g": str(gym_id),
                "activity_type": CLASS_ATTENDED_ACTIVITY_TYPE,
                "class_id": str(class_id),
            },
        )

    async def _reverse_auto_end(
        self,
        session: AsyncSession,
        member_id: UUID,
        item_id: UUID | None,
    ) -> UUID | None:
        """Clear the pack's auto-end end_date if the removal drops it below
        capacity. None item_id (no-membership attendance) charged nothing, so
        there is nothing to reverse."""
        if item_id is None:
            return None
        info = await self._fetchone(
            session,
            load_sql(SQL_DIR / "checkin_load_membership_for_reversal.sql"),
            {"item_id": str(item_id)},
        )
        if info is None or not self._is_depletion_auto_end(info):
            return None
        remaining = await self._count_attendance(session, item_id, member_id)
        capacity = int(info["class_count"]) * int(info["quantity"])
        if remaining >= capacity:
            return None
        await session.execute(
            text(
                load_sql(
                    CLASSES_SQL_DIR / "classes_undo_reverse_membership_end.sql"
                )
            ),
            {"item_id": str(item_id), "member_id": str(member_id)},
        )
        return item_id

    async def _count_attendance(
        self, session: AsyncSession, item_id: UUID, member_id: UUID
    ) -> int:
        """Attendance still recorded against the pack (post-delete)."""
        row = await self._fetchone(
            session,
            load_sql(CLASSES_SQL_DIR / "classes_undo_count_attendance.sql"),
            {"item_id": str(item_id), "member_id": str(member_id)},
        )
        return int(row["attendance_count"]) if row else 0

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
    def _is_depletion_auto_end(info: dict) -> bool:
        """Whether the pack's end_date is a depletion auto-end to reverse: a
        non-null end_date on a finite-count trial / one_time pack."""
        if info["end_date"] is None or info["class_count"] is None:
            return False
        return PlanType(info["plan_type"]) in (
            PlanType.trial,
            PlanType.one_time,
        )

    @staticmethod
    async def _fetchone(
        session: AsyncSession, sql: str, params: dict
    ) -> dict | None:
        """One row of a query as a dict, or None."""
        row = (
            (await session.execute(text(sql), params)).mappings().fetchone()
        )
        return dict(row) if row else None
