"""CRUD over ``class_instance_exceptions`` and ``class_range_exceptions``.

Instance exceptions upsert (unique per ``(class_id, original_date)``); range
exceptions insert. A reschedule (``new_date`` set) is the CRM's single
``POST /exceptions/instance`` move: it delegates the time-aware conflict check
and the attendance wipe / re-date to the reschedule engine on
``ClassesUndoService`` (the owner of the teardown + transaction machinery), then
writes the full override row in the SAME transaction so the whole move is atomic.

A non-reschedule override (``new_date`` unset — retime / instructor / capacity /
cancel) is a plain idempotent upsert. It has no attendance side effects, but
when the occurrence is already MATERIALIZED (a ``class_history`` row exists for
``original_date``), it ALSO syncs that row's snapshot (``occurred_at`` +
``duration_minutes`` + ``instructor_id``) to the override's effective values, in
the SAME transaction as the exception write — see ``_upsert_plain_override``.
This reuses ``ClassesUndoService``'s ``find_history_id`` (is it materialized?),
``resolve_default_instructor`` (the weekday fallback when an override omits
``new_instructor_id``), and ``sync_history_snapshot`` (the write), so the
generalized sync logic lives in exactly one place.
"""

import logging
from datetime import UTC, date, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

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
from src.classes.service.classes_undo_service import ClassesUndoService
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
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
_CLASS_NOT_FOUND_MSG = "Class not found"


class ClassesExceptionsService:
    """Instance + range exception writes / reads for a class.

    A reschedule move (``new_date`` on an instance-exception upsert) is delegated
    to the shared reschedule engine on ``ClassesUndoService``: the two reschedule
    entry points (this upsert and the ``/reschedule`` endpoint) share one
    time-aware conflict check + one attendance wipe / re-date, so they can never
    diverge. ``RescheduleConflictError`` is raised from that engine (imported
    from the undo module to avoid a circular dependency).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        undo_service: ClassesUndoService,
    ) -> None:
        self._db_pool = db_pool
        self._undo_service = undo_service

    async def upsert_instance_exception(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> ClassInstanceExceptionResponse:
        """Insert or replace the single-date override for ``original_date``.

        When ``new_date`` is set (a reschedule), the whole move — the time-aware
        conflict check, the attendance wipe (future) / re-date+resync (today /
        past), and the exception write — runs atomically via the reschedule
        engine (``_reschedule_with_attendance``); the exact target instant
        already being taken by a non-cancelled occurrence raises
        ``RescheduleConflictError``. Otherwise this is a plain override upsert
        (``_upsert_plain_override``): no attendance-moving effects, but a
        MATERIALIZED occurrence gets its history snapshot synced to the
        override's effective values in the same transaction.
        """
        if request.new_date is not None:
            return await self._reschedule_with_attendance(
                class_id, gym_id, request
            )
        return await self._upsert_plain_override(class_id, gym_id, request)

    async def _upsert_plain_override(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> ClassInstanceExceptionResponse:
        """Write the plain (non-reschedule) override for ``original_date``.

        When ``original_date`` is already materialized (a ``class_history`` row
        exists for it, gym-local), ALSO syncs that row's snapshot — ``occurred_at``
        / ``duration_minutes`` / ``instructor_id`` — to the override's effective
        values, in the SAME transaction as the exception write. Without this, a
        retime / re-instructor / re-duration edit on a past occurrence would
        only ever reach the expander (the future/unmaterialized view) and never
        the immutable past board, which renders straight from ``class_history``
        (``classes_board_past_history.sql``). A non-materialized occurrence is a
        plain upsert with no history effect — materialize-on-read applies the
        override once the occurrence is first attended.
        """
        class_row = await self._read_one(
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        if class_row is None:
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        gym_tz = await self._gym_timezone(class_row["gym_id"])

        sql = load_sql(SQL_DIR / "classes_instance_exception_upsert.sql")
        params = self._upsert_params(class_id, gym_id, request)
        try:
            async with self._db_pool.session() as session:
                history_id = await self._undo_service.find_history_id(
                    session, class_id, request.original_date, gym_tz
                )
                if history_id is not None:
                    await self._sync_materialized_snapshot(
                        session, class_row, request, history_id, gym_tz
                    )
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
        return ClassInstanceExceptionResponse(**row)

    async def _sync_materialized_snapshot(
        self,
        session: AsyncSession,
        class_row: dict,
        request: ClassInstanceExceptionUpsertRequest,
        history_id: UUID,
        gym_tz: str,
    ) -> None:
        """Compute the override's effective ``occurred_at`` / duration /
        instructor and sync them onto the materialized history row.

        The fallback rule matches the reschedule path exactly: an override
        field falls back to the class default when unset (``request.new_*`` if
        given, else the class's own default), never to any prior exception.
        Instructor's "class default" is the WEEKDAY default for
        ``original_date`` (``ClassesUndoService.resolve_default_instructor``),
        since (unlike time/duration) it is weekday-dependent.
        """
        effective_time = (
            request.new_class_time
            if request.new_class_time is not None
            else class_row["class_time"]
        )
        effective_duration = (
            request.new_duration_minutes
            if request.new_duration_minutes is not None
            else class_row["duration_minutes"]
        )
        effective_instructor = (
            request.new_instructor_id
            if request.new_instructor_id is not None
            else self._undo_service.resolve_default_instructor(
                class_row, request.original_date
            )
        )
        occurred_at = datetime.combine(
            request.original_date, effective_time, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)
        await self._undo_service.sync_history_snapshot(
            session,
            history_id,
            occurred_at,
            effective_duration,
            effective_instructor,
        )

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

    # -- reschedule (delegates to the shared engine) ---------------------

    async def _reschedule_with_attendance(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> ClassInstanceExceptionResponse:
        """Move the occurrence to ``request.new_date``, attendance following.

        The moved occurrence's effective start time = ``request.new_class_time``
        when set, else the class default; its duration =
        ``request.new_duration_minutes`` when set, else the class default; its
        instructor = ``request.new_instructor_id`` when set, else the WEEKDAY
        default for ``original_date`` (``ClassesUndoService
        .resolve_default_instructor`` — instructor is weekday-dependent, unlike
        time/duration). The full upsert REPLACES the row, so an omitted override
        falls back to the class default, not to any prior override. The
        conflict check + the attendance wipe / re-date+resync come from the
        shared engine; the override row is written in the SAME transaction as
        the attendance handling.
        """
        class_row = await self._read_one(
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        if class_row is None:
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        gym_tz = await self._gym_timezone(class_row["gym_id"])

        new_date = request.new_date
        effective_time = (
            request.new_class_time
            if request.new_class_time is not None
            else class_row["class_time"]
        )
        effective_duration = (
            request.new_duration_minutes
            if request.new_duration_minutes is not None
            else class_row["duration_minutes"]
        )
        effective_instructor = (
            request.new_instructor_id
            if request.new_instructor_id is not None
            else self._undo_service.resolve_default_instructor(
                class_row, request.original_date
            )
        )
        new_occurred_at = datetime.combine(
            new_date, effective_time, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)

        await self._undo_service.assert_no_reschedule_conflict(
            class_row,
            class_id,
            request.original_date,
            new_date,
            effective_time,
            new_occurred_at,
            gym_tz,
        )

        is_future = new_date > gym_today(gym_tz)
        row = await self._write_reschedule(
            class_id,
            gym_id,
            request,
            new_occurred_at,
            effective_duration,
            effective_instructor,
            is_future,
            gym_tz,
        )
        return ClassInstanceExceptionResponse(**row)

    async def _write_reschedule(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
        new_occurred_at: datetime,
        effective_duration: int,
        effective_instructor: UUID | None,
        is_future: bool,
        gym_tz: str,
    ) -> dict:
        """Attendance handling + the full override upsert in ONE transaction.

        A bad instructor / duration on the override surfaces as an
        ``IntegrityError`` → 400 (the full upsert's dominant failure); a redate
        instant-collision that slipped past the conflict check would too, but the
        conflict check covers it in the common case.
        """
        sql = load_sql(SQL_DIR / "classes_instance_exception_upsert.sql")
        try:
            async with self._db_pool.session() as session:
                await self._undo_service.apply_reschedule_attendance(
                    session,
                    class_id,
                    gym_id,
                    request.original_date,
                    new_occurred_at,
                    effective_duration,
                    effective_instructor,
                    is_future,
                    gym_tz,
                )
                row = (
                    (
                        await session.execute(
                            text(sql),
                            self._upsert_params(class_id, gym_id, request),
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_EXCEPTION_MSG) from exc
        if not row:
            raise RuntimeError("Write did not return a row")
        return dict(row)

    @staticmethod
    def _upsert_params(
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> dict:
        """Bind params for the full ``class_instance_exception_upsert.sql``."""
        return {
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
