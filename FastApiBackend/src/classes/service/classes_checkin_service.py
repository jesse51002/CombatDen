"""Service for checking a member into a class."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.classes import SQL_DIR
from src.classes.schema.classes_schema import CheckinRequest, CheckinResponse
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class ClassesCheckinService:
    """Inserts a row in ``member_attendance`` and bumps ``members.last_class``.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def checkin(self, request: CheckinRequest) -> CheckinResponse:
        """Record attendance for a member at a class instance.

        The ``UNIQUE (member_id, class_history_id)`` constraint
        enforces idempotence — a duplicate check-in returns the
        existing log_id with ``already_checked_in = True``.
        """
        insert_sql = load_sql(SQL_DIR / "insert_attendance.sql")
        existing_sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        last_class_sql = load_sql(SQL_DIR / "update_last_class.sql")

        params = {
            "member_id": str(request.member_id),
            "gym_id": str(request.gym_id),
            "class_history_id": str(request.class_history_id),
        }

        async with self._db_pool.session() as session:
            insert_row = (await session.execute(text(insert_sql), params)).mappings().fetchone()

            if insert_row:
                log_id: UUID = insert_row["log_id"]
                already_checked_in = False
            else:
                existing_row = (
                    (
                        await session.execute(
                            text(existing_sql),
                            {
                                "member_id": params["member_id"],
                                "class_history_id": params["class_history_id"],
                            },
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                if not existing_row:
                    raise RuntimeError("Attendance row missing after ON CONFLICT DO NOTHING")
                log_id = existing_row["log_id"]
                already_checked_in = True

            await session.execute(
                text(last_class_sql),
                {
                    "member_id": params["member_id"],
                    "class_history_id": params["class_history_id"],
                },
            )
            await session.commit()

        return CheckinResponse(
            log_id=log_id,
            member_id=request.member_id,
            class_history_id=request.class_history_id,
            already_checked_in=already_checked_in,
        )
