"""Database reads for the gated class check-in.

The occurrence-resolution reads (instance / range exception lists, gym
timezone) come from the ``classes`` domain's ``sql/`` dir — they are inputs to
the canonical ``ClassesExpander``, which stays in ``classes``. This is the same
one-way ``checkin -> classes`` dependency the occurrence resolver expresses by
importing ``ClassesExpander`` / ``ClassesMaterializer``. The check-in-only reads
(class-for-checkin, attendance count, existing attendance, plan eligibility)
live in this domain's own ``sql/`` dir.
"""

from datetime import date, datetime
from pathlib import Path
from uuid import UUID

from sqlalchemy import text

from src.checkin import SQL_DIR
from src.classes import SQL_DIR as CLASSES_SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_local_day_bounds_utc
from src.shared.sql_loader import load_sql


class CheckinQueries:
    """Read-side queries for the check-in flow.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_class_for_checkin(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> dict | None:
        """Load the class (+ its capacity override for the date) for resolve.

        Returns the expander-relevant columns, the gate flags
        (``is_active`` / ``is_deleted``), ``max_capacity`` / ``points_worth`` /
        ``class_name`` / ``allowed_plan_ids``, and ``exception_max_capacity``
        (the instance exception's per-occurrence capacity override, if any).
        None when no such class exists for the gym.
        """
        sql = load_sql(SQL_DIR / "classes_get_for_checkin.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_id": str(class_id),
                            "gym_id": str(gym_id),
                            "occurrence_date": occurrence_date,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return dict(row) if row else None

    async def get_instance_exceptions(
        self,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Instance exceptions for a class whose original_date is in window."""
        return await self._read_all(
            CLASSES_SQL_DIR / "classes_instance_exception_list.sql",
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def get_range_exceptions(
        self,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Range exceptions for a class overlapping the window."""
        return await self._read_all(
            CLASSES_SQL_DIR / "classes_range_exception_list.sql",
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def get_gym_timezone(self, gym_id: UUID) -> str | None:
        """Read the gym's IANA timezone (for the expand / occurred_at)."""
        sql = load_sql(CLASSES_SQL_DIR / "get_gym_timezone.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["timezone"] if row else None

    async def get_signup_or_attended_members(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> set[UUID]:
        """Distinct members signed-up OR attended for one occurrence.

        The capacity-reserving set (``signup_capacity_count.sql``) — shared by
        ``SignupService``'s create-time capacity check and the check-in
        capacity gate, so a member already counted (a prior sign-up, or a
        prior/walk-in check-in) is never double-counted against the room.

        Raises:
            ValueError: If the gym does not exist.
        """
        gym_tz = await self.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError("Gym not found")
        day_start, day_end = gym_local_day_bounds_utc(occurrence_date, gym_tz)
        sql = load_sql(SQL_DIR / "signup_capacity_count.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_id": str(class_id),
                            "gym_id": str(gym_id),
                            "occurrence_date": occurrence_date,
                            "day_start": day_start,
                            "day_end": day_end,
                        },
                    )
                )
                .mappings()
                .all()
            )
        return {row["member_id"] for row in rows}

    async def get_existing_attendance(
        self,
        member_id: UUID,
        class_history_id: UUID,
    ) -> dict | None:
        """Return the existing attendance row, if any (idempotency)."""
        sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(member_id),
                            "class_history_id": str(class_history_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return dict(row) if row else None

    async def get_eligible_plans(
        self,
        gym_id: UUID,
        class_id: UUID,
        plan_ids: list[UUID],
    ) -> set[UUID]:
        """Query which of the plans may attend the given class."""
        sql = load_sql(SQL_DIR / "class_plan_eligibility.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(gym_id),
                            "class_id": str(class_id),
                            "plan_ids": [str(pid) for pid in plan_ids],
                        },
                    )
                )
                .mappings()
                .all()
            )
        return {row["plan_id"] for row in rows}

    async def find_history_for_day(
        self,
        class_id: UUID,
        gym_id: UUID,
        day_start: datetime,
        day_end: datetime,
    ) -> UUID | None:
        """Find the materialized class_history row for a gym-local calendar day.

        ``day_start`` / ``day_end`` are the day's UTC bounds (gym-local midnight
        to the next, converted to UTC), so a per-occurrence time override still
        resolves to the same row. None when the occurrence was never
        materialized (no check-ins yet).
        """
        sql = load_sql(SQL_DIR / "find_history_for_day.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_id": str(class_id),
                            "gym_id": str(gym_id),
                            "day_start": day_start,
                            "day_end": day_end,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["class_history_id"] if row else None

    async def get_roster(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        day_start: datetime,
        day_end: datetime,
    ) -> list[dict]:
        """List everyone who signed up OR attended one occurrence.

        Joins ``class_signups`` and ``member_attendance`` (attendance via the
        occurrence's ``class_history`` row, matched to the gym-local calendar
        day) to ``members`` for ``full_name``, flagging each with
        ``signed_up`` / ``attended`` and carrying the billing attribution
        (``plan_id`` / ``item_id``, NULL when not attended). Gym-scoped for
        the employee auth boundary.
        """
        return await self._read_all(
            SQL_DIR / "roster_for_occurrence.sql",
            {
                "class_id": str(class_id),
                "gym_id": str(gym_id),
                "occurrence_date": occurrence_date,
                "day_start": day_start,
                "day_end": day_end,
            },
        )

    async def _read_all(self, sql_path: Path, params: dict) -> list[dict]:
        sql = load_sql(sql_path)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
