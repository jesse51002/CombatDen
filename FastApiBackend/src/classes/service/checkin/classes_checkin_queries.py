"""Database reads for the gated class check-in."""

from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.classes.schema.classes_schema import CheckinRequest
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class ClassesCheckinQueries:
    """Read-side queries for the check-in flow.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def resolve_class_id(
        self,
        request: CheckinRequest,
    ) -> UUID | None:
        """Resolve the class a class_history occurrence belongs to."""
        sql = load_sql(SQL_DIR / "resolve_class.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_history_id": str(request.class_history_id),
                            "gym_id": str(request.gym_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["class_id"] if row else None

    async def get_existing_attendance(
        self,
        request: CheckinRequest,
    ) -> dict | None:
        """Return the existing attendance row, if any (idempotency)."""
        sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(request.member_id),
                            "class_history_id": str(request.class_history_id),
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

    async def resolve_item_id(
        self,
        request: CheckinRequest,
        plan_id: UUID,
    ) -> UUID | None:
        """Pick the concrete active membership row to charge for a plan."""
        sql = load_sql(SQL_DIR / "select_membership_item.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(request.member_id),
                            "gym_id": str(request.gym_id),
                            "plan_id": str(plan_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["item_id"] if row else None
