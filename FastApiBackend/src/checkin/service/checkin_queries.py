"""Database reads for the gated class check-in.

Occurrence resolution (the class's schedule versions + its instance/range
exceptions) reads checkin-owned SQL mirroring the shapes ``classes`` uses for
its own reads — each domain owns its SQL files. The version-EXPANSION code
(``ClassesVersionExpander``) still comes from the ``classes`` domain: the
one-way ``checkin -> classes`` dependency is at the code level, not the SQL
level. The check-in-only reads (class-for-checkin, attendance / roster /
eligibility) live in this domain's own ``sql/`` dir too.
"""

from datetime import date
from pathlib import Path
from uuid import UUID

from sqlalchemy import text

from src.checkin import SQL_DIR
from src.shared.database import DirectDatabasePool
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

        Returns the IDENTITY columns (``max_capacity`` / ``allowed_plan_ids`` /
        ``points_worth`` / ``class_name``), the gate flags (``is_active`` /
        ``is_deleted``), and ``exception_max_capacity`` (the instance
        exception's per-occurrence capacity override, if any). None when no
        such class exists for the gym.
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

    async def get_schedule_versions(self, class_id: UUID) -> list[dict]:
        """ALL of the class's schedule versions, oldest first — occurrence
        resolution needs the full version history (not just the current one)
        so a past-dated check-in / sign-up resolves against whichever
        version owned that date."""
        return await self._read_all(
            SQL_DIR / "checkin_load_schedules.sql", {"class_id": str(class_id)}
        )

    async def get_instance_exceptions(
        self,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[dict]:
        """Instance exceptions for a class whose original_date is in window."""
        return await self._read_all(
            SQL_DIR / "checkin_instance_exceptions_for_window.sql",
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
            SQL_DIR / "checkin_range_exceptions_for_window.sql",
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def get_signup_or_attended_members(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> set[UUID]:
        """Distinct members signed-up OR attended for one occurrence.

        The capacity-reserving set (``signup_capacity_count.sql``), keyed
        directly by the occurrence's identity (``class_id``,
        ``original_date``) — shared by ``SignupService``'s create-time
        capacity check and the check-in capacity gate, so a member already
        counted (a prior sign-up, or a prior/walk-in check-in) is never
        double-counted against the room.
        """
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
        class_id: UUID,
        original_date: date,
    ) -> dict | None:
        """Return the existing attendance row, if any (idempotency), keyed
        by the occurrence's identity (``class_id``, ``original_date``)."""
        sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(member_id),
                            "class_id": str(class_id),
                            "original_date": original_date,
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

    async def get_roster(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> list[dict]:
        """List everyone who signed up OR attended one occurrence.

        Joins ``class_signups`` and ``member_attendance`` (both keyed
        directly by the occurrence's identity, ``class_id`` +
        ``original_date``) to ``members`` for ``full_name``, flagging each
        with ``signed_up`` / ``attended`` and carrying the billing
        attribution (``plan_id`` / ``item_id``, NULL when not attended).
        Gym-scoped for the employee auth boundary.
        """
        return await self._read_all(
            SQL_DIR / "roster_for_occurrence.sql",
            {
                "class_id": str(class_id),
                "gym_id": str(gym_id),
                "occurrence_date": occurrence_date,
            },
        )

    async def _read_all(self, sql_path: Path, params: dict) -> list[dict]:
        sql = load_sql(sql_path)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
