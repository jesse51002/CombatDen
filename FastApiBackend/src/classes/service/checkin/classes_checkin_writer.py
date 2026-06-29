"""Transactional write path for the gated class check-in."""

import json
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.classes import SQL_DIR
from src.classes.schema.classes_schema import OccurrenceContext
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

_FALLBACK_TIMEZONE = "America/Chicago"
# member_activities.activity_type value for a recorded class attendance (the
# seed's convention — see Database/python_data/generators/activities.py).
CLASS_ATTENDED_ACTIVITY_TYPE = "class_attended"


class ClassesCheckinWriter:
    """Inserts attendance, bumps last_class, awards points, and auto-ends.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def write_checkin(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        plan_id: UUID,
        item_id: UUID,
        should_end: bool,
    ) -> tuple[UUID, bool, int]:
        """Insert attendance, bump last_class, award points, conditionally end.

        Points are awarded ONLY on a newly-inserted attendance row, in the same
        transaction: an ON CONFLICT idempotent repeat awards nothing.

        Returns:
            ``(log_id, already_checked_in, points_awarded)``.
            ``already_checked_in`` is True only when a concurrent check-in won
            the INSERT race; in that case nothing is awarded and no auto-end is
            performed (``points_awarded`` is 0).
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
                            "member_id": str(member_id),
                            "gym_id": str(ctx.gym_id),
                            "class_history_id": str(ctx.class_history_id),
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
                                "member_id": str(member_id),
                                "class_history_id": str(ctx.class_history_id),
                            },
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                if not existing:
                    raise RuntimeError(
                        "Attendance row missing after ON CONFLICT DO NOTHING"
                    )
                await session.commit()
                return existing["log_id"], True, 0

            log_id: UUID = insert_row["log_id"]

            await session.execute(
                text(last_class_sql),
                {
                    "member_id": str(member_id),
                    "class_history_id": str(ctx.class_history_id),
                },
            )

            await self._award_points(session, ctx, member_id)

            if should_end:
                await self._end_membership(session, ctx, member_id, item_id)

            await session.commit()
            return log_id, False, ctx.points_worth

    async def _award_points(
        self,
        session: AsyncSession,
        ctx: OccurrenceContext,
        member_id: UUID,
    ) -> None:
        """Add the class's points to the member and log a class_attended row."""
        points_sql = load_sql(SQL_DIR / "classes_award_points.sql")
        activity_sql = load_sql(SQL_DIR / "classes_insert_activity.sql")

        await session.execute(
            text(points_sql),
            {
                "points": ctx.points_worth,
                "m": str(member_id),
                "g": str(ctx.gym_id),
            },
        )
        info = json.dumps(
            {
                "class_id": str(ctx.class_id),
                "class_name": ctx.class_name,
                "points": ctx.points_worth,
            }
        )
        await session.execute(
            text(activity_sql),
            {
                "m": str(member_id),
                "g": str(ctx.gym_id),
                "activity_type": CLASS_ATTENDED_ACTIVITY_TYPE,
                "info": info,
            },
        )

    async def _end_membership(
        self,
        session: AsyncSession,
        ctx: OccurrenceContext,
        member_id: UUID,
        item_id: UUID,
    ) -> None:
        """Set end_date on the charged membership to end it (within session)."""
        tz_sql = load_sql(SQL_DIR / "get_gym_timezone.sql")
        end_sql = load_sql(SQL_DIR / "end_membership.sql")

        tz_row = (
            (
                await session.execute(
                    text(tz_sql),
                    {"gym_id": str(ctx.gym_id)},
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
                "member_id": str(member_id),
                "end_date": gym_today(timezone),
            },
        )
