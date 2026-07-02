"""CRUD over ``class_instance_exceptions`` and ``class_range_exceptions``.

Instance exceptions upsert (unique per ``(class_id, original_date,
original_time)`` — one exception per exact SLOT, so two same-day occurrences
of one class are overridden independently); range exceptions insert. An
exception binds to the occurrence's ORIGINAL slot — the identity key
attendance and sign-ups store — so overrides and reschedules never re-key
anything. Override fallbacks (duration / slot instructor) resolve against the
version OWNING the slot: a retro edit on a slot from an older schedule
version falls back to THAT version's defaults, never the current one's.

A reschedule (``new_date`` set) is the CRM's single ``POST
/exceptions/instance`` move: it delegates the time-aware conflict check and
the attendance wipe / occurred_at re-sync to the reschedule engine on
``ClassesUndoService`` (the owner of the teardown + transaction machinery),
then writes the full override row in the SAME transaction so the whole move
is atomic. Sign-ups always carry (the identity key is untouched).

A non-reschedule override (``new_date`` unset — retime / instructor /
capacity / cancel) is a plain idempotent upsert. Its one side effect: when
the (non-cancelled) occurrence has attendance, the override's effective start
instant is re-synced onto those rows' denormalized ``occurred_at`` in the
SAME transaction (``sync_attendance_occurred_at`` — a no-op when nobody
attended), so the streak / cycle-count / last-class window SQL keeps reading
the right instant.

A CANCEL range (``create_range_exception`` with ``is_cancelled=True``)
additionally tears down the range's covered occurrences in the SAME
transaction as the range insert (``_write_range_and_teardown``). The teardown
runs per SLOT — a range covers every slot of its covered dates, and each
candidate slot (one still carrying a live reservation or attendance row) is
decided independently: it is LEFT ALONE when a non-cancelled instance
exception governs that exact slot instead — same-slot override or moved
elsewhere, either way the range never applies to a slot with ANY instance
exception on it — or when an earlier-created covering range already renders
it; otherwise it is torn down (``ClassesUndoService.teardown_occurrence``)
ONLY when its original slot instant is still at/after now. An already-run
occurrence keeps its attendance even when covered by a retroactive range
cancel — deliberately asymmetric with the future case: mass-clawing-back
historical points from one bulk range action is a shock hazard, so a gym
that wants that cancels the single occurrence instead (which tears down
regardless of instant). A multi-slot day under a covering cancel can thus
split: the 06:00 that already ran keeps its attendance while the upcoming
18:30 is torn down. An instructor-substitution range (``is_cancelled=False``)
never tears anything down.

``update_range_exception`` moves an existing range's dates
(``start_date``/``end_date`` only — ``is_cancelled``/``new_instructor_id``
are fixed at creation). For a CANCEL range this re-runs the SAME teardown
pass over the range's NEW coverage, atomically with the date UPDATE — since
``_range_cancel_candidates`` only ever returns slots that still carry a live
reservation/attendance row, re-running it over the full new window is
naturally idempotent (an already-torn-down slot has nothing left to find). A
slot that falls OUT of the new coverage is never explicitly restored — it
simply stops being covered on the next expansion. An instructor-substitution
range's dates just move, no teardown. ``delete_range_exception`` removes a
range outright; its covered slots revive the same passive way.
"""

import logging
from datetime import UTC, date, datetime, time
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
    ClassRangeExceptionUpdateRequest,
)
from src.classes.schema.classes_expander_schema import ExpanderScheduleVersion
from src.classes.service.classes_undo_service import ClassesUndoService
from src.shared.database import DirectDatabasePool
from src.shared.db_rows import fetch_all, fetch_one
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
_RANGE_EXCEPTION_NOT_FOUND_MSG = "Range exception not found"


class ClassesExceptionsService:
    """Instance + range exception writes / reads for a class.

    A reschedule move (``new_date`` on an instance-exception upsert) is
    delegated to the shared reschedule engine on ``ClassesUndoService``: the
    two reschedule entry points (this upsert and the ``/reschedule`` endpoint)
    share one time-aware conflict check + one attendance wipe / re-sync, so
    they can never diverge. ``RescheduleConflictError`` is raised from that
    engine (imported from the undo module to avoid a circular dependency).
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

        When ``new_date`` is set (a reschedule), the whole move — the
        time-aware conflict check, the attendance wipe (future) / occurred_at
        re-sync (today / past), and the exception write — runs atomically via
        the reschedule engine (``_reschedule_with_attendance``); the exact
        target instant already being taken by a non-cancelled occurrence
        raises ``RescheduleConflictError``. Otherwise this is a plain
        override upsert (``_upsert_plain_override``).
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
        """Write the plain (non-reschedule) override for the exact
        ``(original_date, original_time)`` slot.

        When the slot exists (the recurrence emits it) and the override
        doesn't cancel it, the override's effective start instant —
        ``new_class_time`` when set, else the slot's own time, interpreted in
        the owning version's frozen timezone — is re-synced onto the
        occurrence's attendance rows in the SAME transaction as the exception
        write (a no-op when nobody attended; a same-day sibling slot's rows
        are never touched). A CANCEL (``is_cancelled=True``, the path the
        CRM's "Cancel this class" uses) runs the SAME teardown as the
        dedicated cancel endpoint — attendance reversed with points clawed
        back + the occurrence's sign-ups deleted — via the undo service's
        shared ``teardown_occurrence``, in the same transaction, so the two
        cancel entry points can never diverge. An override on a slot the
        recurrence never emits is a plain, inert upsert.
        """
        await self._assert_class_exists(class_id)
        owning = await self._undo_service.owning_version(
            class_id, request.original_date, request.original_time
        )

        sql = load_sql(SQL_DIR / "classes_instance_exception_upsert.sql")
        params = self._upsert_params(class_id, gym_id, request)
        try:
            async with self._db_pool.session() as session:
                if request.is_cancelled:
                    await self._undo_service.teardown_occurrence(
                        session,
                        class_id,
                        gym_id,
                        request.original_date,
                        request.original_time,
                    )
                elif owning is not None:
                    await self._undo_service.sync_attendance_occurred_at(
                        session,
                        class_id,
                        request.original_date,
                        request.original_time,
                        self._effective_start(owning, request),
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

    async def create_range_exception(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassRangeExceptionCreateRequest,
    ) -> ClassRangeExceptionResponse:
        """Create a continuous-range cancel / instructor-substitution override.

        A CANCEL range (``is_cancelled=True``) additionally tears down the
        range's covered occurrences in the SAME transaction as the range
        insert — see ``_write_range_and_teardown`` and the module docstring
        for the precedence + past-instant rules. An instructor-substitution
        range (``is_cancelled=False``) is the plain insert only — the class
        still runs, so nothing is torn down.
        """
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
        row = await self._write_range_and_teardown(
            class_id,
            gym_id,
            sql,
            params,
            is_cancelled=request.is_cancelled,
            start_date=request.start_date,
            end_date=request.end_date,
        )
        return ClassRangeExceptionResponse(**row)

    async def update_range_exception(
        self,
        class_id: UUID,
        gym_id: UUID,
        exception_id: UUID,
        request: ClassRangeExceptionUpdateRequest,
    ) -> ClassRangeExceptionResponse:
        """Move an existing range exception's dates.

        For a CANCEL range this re-runs the SAME teardown pass as create,
        over the range's NEW ``[start_date, end_date]``, atomically with the
        date UPDATE — see the module docstring. An instructor-substitution
        range's dates just move; nothing is torn down.

        Raises:
            ValueError: ``exception_id`` doesn't belong to this class (404).
        """
        existing = await self._load_range_exception(class_id, exception_id)
        sql = load_sql(SQL_DIR / "classes_range_exception_update.sql")
        params = {
            "class_id": str(class_id),
            "exception_id": str(exception_id),
            "start_date": request.start_date,
            "end_date": request.end_date,
        }
        row = await self._write_range_and_teardown(
            class_id,
            gym_id,
            sql,
            params,
            is_cancelled=existing["is_cancelled"],
            start_date=request.start_date,
            end_date=request.end_date,
        )
        return ClassRangeExceptionResponse(**row)

    async def delete_range_exception(
        self,
        class_id: UUID,
        exception_id: UUID,
    ) -> ClassRangeExceptionResponse:
        """Remove a range exception outright.

        Covered dates revive on the next expansion — nothing already torn
        down while the range was active is restored (see the module
        docstring's irreversibility rule).

        Raises:
            ValueError: ``exception_id`` doesn't belong to this class (404).
        """
        row = await self._write_returning(
            load_sql(SQL_DIR / "classes_range_exception_delete.sql"),
            {"class_id": str(class_id), "exception_id": str(exception_id)},
            allow_missing=True,
        )
        if row is None:
            raise ValueError(_RANGE_EXCEPTION_NOT_FOUND_MSG)
        return ClassRangeExceptionResponse(**row)

    async def _load_range_exception(
        self, class_id: UUID, exception_id: UUID
    ) -> dict:
        """The range exception row, scoped to ``class_id``.

        Raises:
            ValueError: no such row for this class (404).
        """
        row = await self._read_one(
            load_sql(SQL_DIR / "classes_range_exception_get.sql"),
            {"class_id": str(class_id), "exception_id": str(exception_id)},
        )
        if row is None:
            raise ValueError(_RANGE_EXCEPTION_NOT_FOUND_MSG)
        return row

    # -- range-cancel teardown ---------------------------------------------

    async def _write_range_and_teardown(
        self,
        class_id: UUID,
        gym_id: UUID,
        sql: str,
        params: dict,
        *,
        is_cancelled: bool,
        start_date: date,
        end_date: date,
    ) -> dict:
        """Run a range-exception write (insert or date-move UPDATE), then —
        only when the range CANCELS (``is_cancelled``) — tear down the
        occurrences it actually cancels over ``[start_date, end_date]`` — all
        in ONE transaction, so the teardown's per-date resolution sees the
        just-written row. Shared by ``create_range_exception`` and
        ``update_range_exception`` so the two entry points can never diverge.
        An instructor-substitution range skips the teardown entirely.
        """
        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                if not row:
                    raise RuntimeError("Write did not return a row")
                if is_cancelled:
                    await self._teardown_covered_occurrences(
                        session, class_id, gym_id, start_date, end_date
                    )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_EXCEPTION_MSG) from exc
        return dict(row)

    async def _teardown_covered_occurrences(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        start_date: date,
        end_date: date,
    ) -> None:
        """Tear down every candidate SLOT in ``[start_date, end_date]`` the
        range actually cancels — see the module docstring for the
        precedence + past-instant rules. A no-op when no candidate slot
        (one still carrying a live reservation or attendance row) exists."""
        candidate_slots = await self._range_cancel_candidates(
            session, class_id, start_date, end_date
        )
        if not candidate_slots:
            return
        versions = await self._undo_service.load_versions(class_id)
        now = datetime.now(UTC)
        for day, slot_time in candidate_slots:
            await self._teardown_if_still_cancelled(
                session, class_id, gym_id, versions, day, slot_time, now
            )

    async def _teardown_if_still_cancelled(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        versions: list[ExpanderScheduleVersion],
        day: date,
        slot_time: time,
        now: datetime,
    ) -> None:
        """Resolve one candidate slot and tear it down only when the range
        genuinely cancels it AND its original slot instant hasn't happened
        yet (INSTANT-based, never day-based — see the module docstring)."""
        exception_row = await self._undo_service.exception_on(
            class_id, day, slot_time, session=session
        )
        if exception_row is not None:
            return  # an instance exception governs this slot, not the range
        occurrences = await self._undo_service.expand_day(
            session, class_id, versions, day
        )
        if any(occ.original_time == slot_time for occ in occurrences):
            return  # an earlier-created covering range still renders it
        slot = self._undo_service.owning_slot(versions, day, slot_time)
        if slot is None:
            return  # not a recurrence slot under the current versions
        _, bare_occurrence = slot
        if bare_occurrence.occurred_at < now:
            return  # already ran -- historical attendance is never wiped
        await self._undo_service.teardown_occurrence(
            session, class_id, gym_id, day, slot_time
        )

    async def _range_cancel_candidates(
        self,
        session: AsyncSession,
        class_id: UUID,
        start_date: date,
        end_date: date,
    ) -> list[tuple[date, time]]:
        """Distinct ``(original_date, original_time)`` slots in
        ``[start_date, end_date]`` still carrying a live reservation or
        attendance row for this class — the only slots a range cancel could
        possibly need to tear down."""
        rows = (
            (
                await session.execute(
                    text(
                        load_sql(
                            SQL_DIR
                            / "classes_range_cancel_candidate_dates.sql"
                        )
                    ),
                    {
                        "class_id": str(class_id),
                        "start_date": start_date,
                        "end_date": end_date,
                    },
                )
            )
            .mappings()
            .all()
        )
        return sorted(
            (row["original_date"], row["original_time"]) for row in rows
        )

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
    ) -> ClassRangeExceptionListResponse:
        """Every range exception ever created for this class, newest first."""
        sql = load_sql(SQL_DIR / "classes_range_exceptions_for_class.sql")
        rows = await self._read_all(sql, {"class_id": str(class_id)})
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
        """Move the occurrence to ``request.new_date``, attendance following
        and sign-ups carrying.

        The moved occurrence's effective start time = ``request
        .new_class_time`` when set, else the OWNING version's slot time. The
        full upsert REPLACES the row, so an omitted override falls back to
        the owning version's default, not to any prior override. The conflict
        check + the attendance wipe / re-sync come from the shared engine;
        the override row is written in the SAME transaction as the attendance
        handling.

        Raises:
            ValueError: the recurrence never emits ``original_date`` — there
                is no occurrence to move (400).
        """
        await self._assert_class_exists(class_id)
        versions = await self._undo_service.load_versions(class_id)
        owning = await self._undo_service.owning_version(
            class_id, request.original_date, request.original_time
        )
        if owning is None:
            raise ValueError(
                f"No class occurrence on {request.original_date} at "
                f"{request.original_time} to reschedule"
            )
        existing = await self._undo_service.exception_on(
            class_id, request.original_date, request.original_time
        )

        new_date = request.new_date
        effective_time = (
            request.new_class_time
            if request.new_class_time is not None
            else request.original_time
        )
        new_occurred_at = datetime.combine(
            new_date, effective_time, tzinfo=ZoneInfo(owning.timezone)
        ).astimezone(UTC)

        await self._undo_service.assert_no_reschedule_conflict(
            class_id,
            versions,
            request.original_date,
            request.original_time,
            new_date,
            effective_time,
            new_occurred_at,
        )

        # A save that re-sends the occurrence's CURRENT landing (the CRM
        # preserves an existing move this way) must not re-run the attendance
        # handling — a future-target wipe would reverse early check-ins over
        # a no-op.
        landing_unchanged = self._undo_service.is_landing_unchanged(
            owning,
            existing,
            request.original_date,
            request.original_time,
            new_date,
            new_occurred_at,
        )
        # INSTANT-based, never day-based: a move to later TODAY is still a
        # move to a class that hasn't happened — its check-ins must wipe.
        is_future = new_occurred_at > datetime.now(UTC)
        row = await self._write_reschedule(
            class_id,
            gym_id,
            request,
            new_occurred_at,
            is_future,
            apply_attendance=not landing_unchanged,
        )
        return ClassInstanceExceptionResponse(**row)

    async def _write_reschedule(
        self,
        class_id: UUID,
        gym_id: UUID,
        request: ClassInstanceExceptionUpsertRequest,
        new_occurred_at: datetime,
        is_future: bool,
        apply_attendance: bool = True,
    ) -> dict:
        """Attendance handling + the full override upsert in ONE transaction.

        A bad instructor / duration on the override surfaces as an
        ``IntegrityError`` → 400 (the full upsert's dominant failure).
        """
        sql = load_sql(SQL_DIR / "classes_instance_exception_upsert.sql")
        try:
            async with self._db_pool.session() as session:
                if apply_attendance:
                    await self._undo_service.apply_reschedule_attendance(
                        session,
                        class_id,
                        gym_id,
                        request.original_date,
                        request.original_time,
                        new_occurred_at,
                        is_future,
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

    # -- helpers -----------------------------------------------------------

    def _effective_start(
        self,
        owning: ExpanderScheduleVersion,
        request: ClassInstanceExceptionUpsertRequest,
    ) -> datetime:
        """The override's effective start instant: ``new_class_time`` when
        set, else the slot's own ``original_time`` — in the owning version's
        frozen timezone."""
        effective_time = (
            request.new_class_time
            if request.new_class_time is not None
            else request.original_time
        )
        return datetime.combine(
            request.original_date,
            effective_time,
            tzinfo=ZoneInfo(owning.timezone),
        ).astimezone(UTC)

    async def _assert_class_exists(self, class_id: UUID) -> None:
        row = await self._read_one(
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        if row is None:
            raise ValueError(_CLASS_NOT_FOUND_MSG)

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
            "original_time": request.original_time,
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

    # -- db helpers ------------------------------------------------------

    async def _write_returning(
        self,
        sql: str,
        params: dict,
        *,
        allow_missing: bool = False,
    ) -> dict | None:
        """Run a write and return its single RETURNING row, mapping a constraint
        violation (bad date range / instructor not in gym) to a 400.

        ``allow_missing`` returns None on a zero-row RETURNING (a legitimate
        "no such row" — e.g. deleting an exception_id that doesn't belong to
        the class) instead of raising; the default treats a missing row as an
        unexpected server error (the create-path's own contract).
        """
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
            if allow_missing:
                return None
            raise RuntimeError("Write did not return a row")
        return dict(row)

    async def _read_one(self, sql: str, params: dict) -> dict | None:
        async with self._db_pool.session() as session:
            return await fetch_one(session, sql, params)

    async def _read_all(self, sql: str, params: dict) -> list[dict]:
        async with self._db_pool.session() as session:
            return await fetch_all(session, sql, params)
