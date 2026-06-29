"""Database reads for the gated class check-in."""

from datetime import date
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class ClassesCheckinQueries:
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
            "classes_instance_exception_list.sql",
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
            "classes_range_exception_list.sql",
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )

    async def get_gym_timezone(self, gym_id: UUID) -> str | None:
        """Read the gym's IANA timezone (for the expand / occurred_at)."""
        sql = load_sql(SQL_DIR / "get_gym_timezone.sql")
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

    async def count_attendance(self, class_history_id: UUID) -> int:
        """Current recorded attendance for an occurrence (capacity gate)."""
        sql = load_sql(SQL_DIR / "classes_count_attendance.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {"class_history_id": str(class_history_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        return int(row["attendance_count"]) if row else 0

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

    async def _read_all(self, sql_file: str, params: dict) -> list[dict]:
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
