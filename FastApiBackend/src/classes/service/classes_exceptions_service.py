"""CRUD over ``class_instance_exceptions`` and ``class_range_exceptions``.

Instance exceptions upsert (unique per ``(class_id, original_date)``); range
exceptions insert. A reschedule (``new_date`` set) is validated against the
expander first so a moved occurrence can never collide with one that already
lands on the target date.
"""

import logging
from datetime import date
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_crud_schema import (
    ClassInstanceExceptionListResponse,
    ClassInstanceExceptionResponse,
    ClassInstanceExceptionUpsertRequest,
    ClassRangeExceptionCreateRequest,
    ClassRangeExceptionListResponse,
    ClassRangeExceptionResponse,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_RANGE_NEEDS_ACTION_MSG = (
    "A range exception must either cancel the range or set a substitute "
    "instructor (is_cancelled or new_instructor_id)."
)
_BAD_EXCEPTION_MSG = (
    "Invalid exception: check the date range and that the instructor is an "
    "employee of this gym."
)


class RescheduleConflictError(Exception):
    """A reschedule target already has a non-cancelled occurrence (→ 409)."""


class ClassesExceptionsService:
    """Instance + range exception writes / reads for a class."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander

    async def upsert_instance_exception(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> ClassInstanceExceptionResponse:
        """Insert or replace the single-date override for ``original_date``.

        When ``new_date`` is set (a reschedule), the move is rejected with a
        ``RescheduleConflictError`` if a non-cancelled occurrence already lands
        on the target date.
        """
        if request.new_date is not None:
            await self._reject_reschedule_conflict(class_id, request)

        sql = load_sql(SQL_DIR / "classes_instance_exception_upsert.sql")
        params = {
            "class_id": str(class_id),
            "gym_id": str(gym_id),
            "original_date": request.original_date,
            "is_cancelled": request.is_cancelled,
            "new_class_time": request.new_class_time,
            "new_duration_minutes": request.new_duration_minutes,
            "new_max_capacity": request.new_max_capacity,
            "new_instructor_id": (
                str(request.new_instructor_id)
                if request.new_instructor_id is not None
                else None
            ),
            "new_date": request.new_date,
        }
        row = await self._write_returning(sql, params)
        return ClassInstanceExceptionResponse(**row)

    async def create_range_exception(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassRangeExceptionCreateRequest,
    ) -> ClassRangeExceptionResponse:
        """Create a continuous-range cancel / instructor-substitution override."""
        if not request.is_cancelled and request.new_instructor_id is None:
            raise ValueError(_RANGE_NEEDS_ACTION_MSG)

        sql = load_sql(SQL_DIR / "classes_range_exception_create.sql")
        params = {
            "class_id": str(class_id),
            "gym_id": str(gym_id),
            "start_date": request.start_date,
            "end_date": request.end_date,
            "is_cancelled": request.is_cancelled,
            "new_instructor_id": (
                str(request.new_instructor_id)
                if request.new_instructor_id is not None
                else None
            ),
        }
        row = await self._write_returning(sql, params)
        return ClassRangeExceptionResponse(**row)

    async def list_instance_exceptions(
        self,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> ClassInstanceExceptionListResponse:
        """Instance exceptions whose original_date falls in the window."""
        sql = load_sql(SQL_DIR / "classes_instance_exception_list.sql")
        rows = await self._read_all(
            sql,
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )
        return ClassInstanceExceptionListResponse(
            items=[ClassInstanceExceptionResponse(**row) for row in rows],
        )

    async def list_range_exceptions(
        self,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> ClassRangeExceptionListResponse:
        """Range exceptions overlapping the window."""
        sql = load_sql(SQL_DIR / "classes_range_exception_list.sql")
        rows = await self._read_all(
            sql,
            {
                "class_id": str(class_id),
                "start_date": start_date,
                "end_date": end_date,
            },
        )
        return ClassRangeExceptionListResponse(
            items=[ClassRangeExceptionResponse(**row) for row in rows],
        )

    # -- reschedule conflict check ---------------------------------------

    async def _reject_reschedule_conflict(
        self,
        class_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> None:
        """Raise if moving the occurrence to ``new_date`` double-books it.

        Two independent checks:
          1. A direct query: another non-cancelled reschedule (different
             ``original_date``) already targets this ``new_date`` — a collision
             the single-day expander below cannot see (it only visits the
             target date itself).
          2. The expander over ``[new_date, new_date]``: the recurrence (or an
             override) already produces a non-cancelled occurrence there.
        """
        target = request.new_date
        if target is None:
            return

        collisions = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_reschedule_collision.sql"),
            {
                "class_id": str(class_id),
                "new_date": target,
                "original_date": request.original_date,
            },
        )
        if collisions:
            raise RescheduleConflictError(
                f"Another occurrence is already rescheduled to {target}."
            )

        class_row = await self._read_one(
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        if class_row is None:
            raise ValueError("Class not found")

        gym_tz = await self._gym_timezone(class_row["gym_id"])
        instances = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_exception_list.sql"),
            {
                "class_id": str(class_id),
                "start_date": target,
                "end_date": target,
            },
        )
        ranges = await self._read_all(
            load_sql(SQL_DIR / "classes_range_exception_list.sql"),
            {
                "class_id": str(class_id),
                "start_date": target,
                "end_date": target,
            },
        )
        occurrences = self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            target,
            target,
            gym_tz,
        )
        if any(occ.effective_date == target for occ in occurrences):
            raise RescheduleConflictError(
                f"A class already occurs on {target}; cannot reschedule onto it."
            )

    async def _gym_timezone(self, gym_id: object) -> str:
        """Read the gym's IANA timezone."""
        row = await self._read_one(
            load_sql(SQL_DIR / "get_gym_timezone.sql"),
            {"gym_id": str(gym_id)},
        )
        if row is None:
            raise ValueError("Gym not found")
        return row["timezone"]

    # -- db helpers ------------------------------------------------------

    async def _write_returning(self, sql: str, params: dict) -> dict:
        """Run a write and return its single RETURNING row, mapping a constraint
        violation (bad date range / instructor not in gym) to a 400."""
        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_EXCEPTION_MSG) from exc
        if not row:
            raise RuntimeError("Write did not return a row")
        return dict(row)

    async def _read_one(self, sql: str, params: dict) -> dict | None:
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return dict(row) if row else None

    async def _read_all(self, sql: str, params: dict) -> list[dict]:
        async with self._db_pool.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return [dict(row) for row in rows]
