"""Transactional write path for the class check-in.

The attribution columns are nullable: a staff check-in of a member with no
covering membership writes the attendance with NULL ``plan_id`` / ``item_id``
(no pack is drawn). Points are still awarded on every newly-inserted row
regardless of attribution; the auto-end only fires for an actual depleting
membership, so a NULL-attribution row never ends anything (``should_end`` is
False with no membership to end).
"""

import json
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.checkin import SQL_DIR
from src.checkin.schema.checkin_schema import (
    CLASS_ATTENDED_ACTIVITY_TYPE,
    ResolvedClass,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import get_gym_timezone, gym_today
from src.shared.sql_loader import load_sql


class CheckinWriter:
    """Inserts attendance, bumps last_class, awards points, and auto-ends.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def write_checkin(
        self,
        resolved_class: ResolvedClass,
        member_id: UUID,
        plan_id: UUID | None,
        item_id: UUID | None,
        should_end: bool,
    ) -> tuple[UUID, bool, int]:
        """Insert attendance, bump last_class, award points, conditionally end.

        ``plan_id`` / ``item_id`` are both None for a no-membership staff
        check-in (the attendance row carries NULL attribution); they are bound
        as SQL NULL. Points are awarded ONLY on a newly-inserted attendance row,
        in the same transaction (membership or not): an ON CONFLICT idempotent
        repeat awards nothing.

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
                            "gym_id": str(resolved_class.gym_id),
                            "class_id": str(resolved_class.class_id),
                            "original_date": resolved_class.occurrence_date,
                            "original_time": resolved_class.original_time,
                            "occurred_at": resolved_class.occurred_at,
                            "plan_id": str(plan_id)
                            if plan_id is not None
                            else None,
                            "item_id": str(item_id)
                            if item_id is not None
                            else None,
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
                                "class_id": str(resolved_class.class_id),
                                "original_date": resolved_class.occurrence_date,
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
                    "occurred_at": resolved_class.occurred_at,
                },
            )

            await self._award_points(session, resolved_class, member_id)

            if should_end:
                await self._end_membership(session, resolved_class, member_id, item_id)

            await session.commit()
            return log_id, False, resolved_class.points_worth

    async def _award_points(
        self,
        session: AsyncSession,
        resolved_class: ResolvedClass,
        member_id: UUID,
    ) -> None:
        """Add the class's points to the member and log a class_attended row."""
        points_sql = load_sql(SQL_DIR / "classes_award_points.sql")
        activity_sql = load_sql(SQL_DIR / "classes_insert_activity.sql")

        await session.execute(
            text(points_sql),
            {
                "points": resolved_class.points_worth,
                "m": str(member_id),
                "g": str(resolved_class.gym_id),
            },
        )
        info = json.dumps(
            {
                "class_id": str(resolved_class.class_id),
                "class_name": resolved_class.class_name,
                "points": resolved_class.points_worth,
            }
        )
        await session.execute(
            text(activity_sql),
            {
                "m": str(member_id),
                "g": str(resolved_class.gym_id),
                "activity_type": CLASS_ATTENDED_ACTIVITY_TYPE,
                "info": info,
            },
        )

    async def _end_membership(
        self,
        session: AsyncSession,
        resolved_class: ResolvedClass,
        member_id: UUID,
        item_id: UUID,
    ) -> None:
        """Set end_date on the charged membership to end it (within session)."""
        end_sql = load_sql(SQL_DIR / "end_membership.sql")
        timezone = await get_gym_timezone(session, resolved_class.gym_id)

        await session.execute(
            text(end_sql),
            {
                "item_id": str(item_id),
                "member_id": str(member_id),
                "end_date": gym_today(timezone),
            },
        )
