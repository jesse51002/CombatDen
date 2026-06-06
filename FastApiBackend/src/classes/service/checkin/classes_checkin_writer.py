"""Transactional write path for the gated class check-in."""

from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.classes.schema.classes_schema import CheckinRequest
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

_FALLBACK_TIMEZONE = "America/Chicago"


class ClassesCheckinWriter:
    """Inserts attendance, bumps last_class, and auto-ends on depletion.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def write_checkin(
        self,
        request: CheckinRequest,
        plan_id: UUID,
        item_id: UUID,
        should_end: bool,
    ) -> tuple[UUID, bool]:
        """Insert attendance, bump last_class, and conditionally auto-end.

        Returns:
            (log_id, already_checked_in). already_checked_in is True only
            when a concurrent check-in won the INSERT race; in that case no
            auto-end is performed.
        """
        insert_sql = load_sql(SQL_DIR / "insert_attendance.sql")
        existing_sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        last_class_sql = load_sql(SQL_DIR / "update_last_class.sql")

        async with self._db_pool.session() as session:
            insert_row = (
                (
                    await session.execute(
                        text(insert_sql),
                        {
                            "member_id": str(request.member_id),
                            "gym_id": str(request.gym_id),
                            "class_history_id": str(request.class_history_id),
                            "plan_id": str(plan_id),
                            "item_id": str(item_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

            if not insert_row:
                existing = (
                    (
                        await session.execute(
                            text(existing_sql),
                            {
                                "member_id": str(request.member_id),
                                "class_history_id": str(request.class_history_id),
                            },
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                if not existing:
                    raise RuntimeError("Attendance row missing after ON CONFLICT DO NOTHING")
                await session.commit()
                return existing["log_id"], True

            log_id: UUID = insert_row["log_id"]

            await session.execute(
                text(last_class_sql),
                {
                    "member_id": str(request.member_id),
                    "class_history_id": str(request.class_history_id),
                },
            )

            if should_end:
                await self._end_membership(session, request, item_id)

            await session.commit()
            return log_id, False

    async def _end_membership(
        self,
        session,
        request: CheckinRequest,
        item_id: UUID,
    ) -> None:
        """Set end_date on the charged membership to end it (within session)."""
        tz_sql = load_sql(SQL_DIR / "get_gym_timezone.sql")
        end_sql = load_sql(SQL_DIR / "end_membership.sql")

        tz_row = (
            (
                await session.execute(
                    text(tz_sql),
                    {"gym_id": str(request.gym_id)},
                )
            )
            .mappings()
            .fetchone()
        )
        timezone = tz_row["timezone"] if tz_row else _FALLBACK_TIMEZONE

        await session.execute(
            text(end_sql),
            {
                "item_id": str(item_id),
                "member_id": str(request.member_id),
                "end_date": gym_today(timezone),
            },
        )
