"""Un-occur (cancel) and reschedule a single class occurrence — Phase 6.

This is billing-adjacent: ``cancel_occurrence`` deletes ``member_attendance``
and may clear an auto-end-on-depletion ``end_date`` on a trial / one_time pack.
It runs every step of a cancel inside ONE transaction so a partial cancel can
never strand the occurrence half-cleaned-up.

Shared reversal — the per-attendee teardown (delete attendance + claw back
points + drop the activity + reverse the pack auto-end) is NOT duplicated here:
``_wipe_occurrence`` loops the ``checkin`` domain's ``CheckinReverser`` over each
attendee, then deletes the now-empty ``class_history``. That makes this a
deliberate ``classes -> checkin`` dependency — the reverse of the usual one-way
``checkin -> classes`` seam — chosen so the reversal lives in exactly one place.
``CheckinReverser`` imports nothing from ``src.classes``, so there is no import
cycle.

Two operations:

* ``cancel_occurrence`` — for a gym-local calendar day: find the materialized
  ``class_history`` row, delete its attendance, reverse the auto-end on any
  trial / one_time pack that drops back below its capacity, delete the history
  row, and write the cancelled instance exception so the day never
  re-materializes. When the occurrence was never materialized (no check-ins),
  only the cancelled exception is written. **Points ARE clawed back** — each
  attendee's ``points_worth`` for the class is subtracted (best-effort:
  ``GREATEST(balance - points, 0)`` floors the balance at 0, so points already
  spent on rewards are never un-bought) and one ``member_activities``
  class_attended row per attendee is dropped.

* ``reschedule_occurrence`` — move an occurrence to ``new_date`` (ANY date —
  past, today, or future; ``original_date`` is only the anchor, not a lower
  bound) by upserting the instance exception's ``new_date``. Attendance follows
  the move: a FUTURE target wipes the moved occurrence's check-ins (the same
  teardown as ``cancel_occurrence``, points clawed back); a today / PAST target
  keeps them, with the class_history row's snapshot (``occurred_at`` +
  ``duration_minutes`` + ``instructor_id``) synced to the move's effective
  values via ``sync_history_snapshot`` so the unchanged attendance rows render
  correctly on the new date's roster. The move is rejected only when the exact
  target instant (new_date + start time) is already taken by a non-cancelled
  occurrence — landing on a busy day at a different time is allowed. The whole
  move (attendance handling + the exception write) runs in ONE transaction. The
  same ``assert_no_reschedule_conflict`` + ``apply_reschedule_attendance``
  engine backs the CRM's ``POST /exceptions/instance`` reschedule
  (``ClassesExceptionsService`` delegates to it), so the two entry points can
  never diverge.

Editing a MATERIALIZED occurrence (past or today, a ``class_history`` row
already exists) always keeps its history snapshot in sync with the edit —
not just on a date move. ``sync_history_snapshot`` (backing SQL:
``classes_history_snapshot_sync.sql``) is the one generalized write for this:
it sets ``occurred_at`` + ``duration_minutes`` + ``instructor_id`` together, so
the past schedule board (which renders straight from ``class_history``, never
by re-expanding — see ``classes_board_past_history.sql``) reflects a retime /
re-instructor / re-duration edit exactly like it already reflected a
reschedule's date move. Both the reschedule keep-path
(``apply_reschedule_attendance``) and ``ClassesExceptionsService``'s same-date
override branch (``upsert_instance_exception`` with ``new_date`` unset) call
it — the exceptions service reuses this service's ``find_history_id`` (is the
occurrence materialized?) and ``resolve_default_instructor`` (the weekday
fallback when an override omits ``new_instructor_id``) to do so in the SAME
transaction as its exception write. A non-materialized occurrence is
unaffected by any of this — the edit is just an exception row; materialize-on-
read applies it when the occurrence is first attended.

Auto-end reversal — IMPORTANT, inexact by necessity: there is no stored link
recording that a membership's ``end_date`` came from an auto-end-on-depletion
(versus a manual end). The best available signal is the depletion recompute:
after deleting the un-occurred attendance, if a trial / one_time pack with a
non-null ``end_date`` is now below its pack capacity (class_count * quantity, the
same capacity the check-in's auto-end uses), the ``end_date`` is treated as the
auto-end and cleared. This CANNOT perfectly distinguish an auto-end from a
manual end on a trial / one_time pack that still has capacity left — a manual
end on a pack that was below capacity will also be cleared. The depletion
recompute is the closest reconstruction available without an attendance->auto-end
link. It is deliberately keyed on the recomputed capacity, NOT on
``occurrence_date == end_date``: a retroactive check-in stamps ``end_date`` = the
day it was written, not the occurrence date, so a date match would miss it.
"""

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.service.checkin_reverser import CheckinReverser
from src.classes import SQL_DIR
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.schema.classes_undo_schema import (
    OccurrenceCancelResponse,
    OccurrenceRescheduleResponse,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import get_gym_timezone, gym_today
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_REDATE_CONFLICT_MSG = (
    "conflict: the reschedule target instant is already taken by a "
    "materialized occurrence."
)


class RescheduleConflictError(Exception):
    """A reschedule target instant already has a non-cancelled occurrence.

    Raised by the shared time-aware conflict check and mapped to a 409 by both
    reschedule routers. Lives here (the reschedule engine's home) so
    ``ClassesExceptionsService`` can import it without a circular dependency —
    exceptions delegates its reschedule to this service.
    """


class ClassesUndoService:
    """Cancel / un-occur and reschedule a single class occurrence.

    Args:
        db_pool: Injected database connection pool (writes run at service_role,
            which append-only RLS requires for the class_history /
            member_attendance deletes).
        expander: The canonical recurrence + exception expander (pure) — used to
            validate the source occurrence and the reschedule target.
        reverser: The shared per-member check-in reverser (from the ``checkin``
            domain). ``_wipe_occurrence`` loops it over every attendee so the
            reversal — attendance delete + points claw-back + activity drop +
            pack auto-end reversal — has a single implementation instead of a
            duplicate here. This is a deliberate ``classes -> checkin`` dependency
            (see the module note); the reverser imports nothing from
            ``src.classes``, so there is no import cycle.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
        reverser: CheckinReverser,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander
        self._reverser = reverser

    # -- cancel / un-occur ----------------------------------------------

    async def cancel_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> OccurrenceCancelResponse:
        """Un-occur one occurrence: delete its attendance + history, reverse any
        auto-end, and write the cancelled exception — all in one transaction.

        Raises:
            ValueError: If the class does not exist for this gym (mapped to 404).
        """
        async with self._db_pool.session() as session:
            await self._verify_class_in_gym(session, class_id, gym_id)
            gym_tz = await get_gym_timezone(session, gym_id)
            history_id = await self.find_history_id(
                session, class_id, occurrence_date, gym_tz
            )

            attendance_deleted = 0
            unended: list[UUID] = []
            if history_id is not None:
                attendance_deleted, unended = await self._wipe_occurrence(
                    session, history_id, gym_id, class_id
                )

            await self._upsert_cancelled_exception(
                session, class_id, gym_id, occurrence_date
            )
            await session.commit()

        return OccurrenceCancelResponse(
            class_id=class_id,
            gym_id=gym_id,
            occurrence_date=occurrence_date,
            class_history_id=history_id,
            attendance_rows_deleted=attendance_deleted,
            memberships_unended=unended,
        )

    async def _wipe_occurrence(
        self,
        session: AsyncSession,
        history_id: UUID,
        gym_id: UUID,
        class_id: UUID,
    ) -> tuple[int, list[UUID]]:
        """Tear down one materialized occurrence's attendance — the shared,
        billing-adjacent teardown used by BOTH ``cancel_occurrence`` and a
        FUTURE reschedule (see ``apply_reschedule_attendance``).

        Loads the class's ``points_worth`` ONCE, enumerates every attendee, then
        loops the shared ``CheckinReverser`` per attendee (delete that member's
        attendance + claw back points, floored at 0 + drop one class_attended
        activity + reverse the auto-end on any trial / one_time pack the delete
        drops back below capacity), and finally deletes the now-empty
        ``class_history``. Runs in the caller's transaction.

        Doing the auto-end reversal per member (delete A's attendance → recompute
        A's pack → reverse if below, then B…) is equivalent to the whole-occurrence
        recompute: each member's pack is independent — the depletion recount
        filters on that member's own ``item_id`` + ``member_id``, so B's delete
        never changes A's count. Order does not matter.

        Returns ``(attendance_rows_deleted, memberships_unended)`` aggregated over
        the per-member reversals.
        """
        points_worth = await self._load_points(session, class_id)
        members = await self._find_all_attendee_members(session, history_id)

        attendance_deleted = 0
        unended: list[UUID] = []
        for member_id in members:
            result = await self._reverser.reverse(
                session,
                history_id,
                member_id,
                gym_id,
                class_id,
                points_worth,
            )
            if result.removed:
                attendance_deleted += 1
            if result.membership_unended is not None:
                unended.append(result.membership_unended)

        await self._delete_history(session, history_id)
        return attendance_deleted, unended

    async def sync_history_snapshot(
        self,
        session: AsyncSession,
        history_id: UUID,
        occurred_at: datetime,
        duration_minutes: int,
        instructor_id: UUID | None,
    ) -> None:
        """Sync a MATERIALIZED occurrence's history snapshot onto its current
        effective values (``occurred_at`` + ``duration_minutes`` +
        ``instructor_id``) — the one generalized write both a today/past
        reschedule's keep-path and a same-date override on an already
        materialized occurrence use, so the past board always renders what
        was actually edited. Its attendance rows (unchanged
        ``class_history_id``) then render on/with the synced values with no
        attendance rewrite. Public: ``ClassesExceptionsService`` calls this
        directly (via its injected ``undo_service``) for the same-date
        override branch, in the SAME transaction as its exception write.
        """
        await session.execute(
            text(load_sql(SQL_DIR / "classes_history_snapshot_sync.sql")),
            {
                "class_history_id": str(history_id),
                "occurred_at": occurred_at,
                "duration_minutes": duration_minutes,
                "instructor_id": (
                    str(instructor_id) if instructor_id is not None else None
                ),
            },
        )

    def resolve_default_instructor(
        self, class_row: dict, when: date
    ) -> UUID | None:
        """The class's weekday-default instructor for ``when``, ignoring any
        existing per-occurrence override.

        Pure (no I/O) — the fallback a full-replace override upsert or
        reschedule uses when the request omits ``new_instructor_id``, so an
        omitted instructor override falls back to the class's weekday slot,
        never to any prior override (mirroring the ``class_time`` /
        ``duration_minutes`` fallback already used for those same paths).
        Delegates to the expander's own weekday-default resolution
        (``ClassesExpander.instructor_for``) so this can never drift from the
        expander's read-path semantics.
        """
        return self._expander.instructor_for(to_expander_class(class_row), when)

    async def _verify_class_in_gym(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Confirm the class exists and belongs to ``gym_id`` BEFORE any delete.

        Guards the auth boundary: without this, a class_id from another gym would
        find + delete that gym's history/attendance (the history find is
        class-scoped) and only fail at the gym-scoped exception upsert — after
        the destructive deletes. A clean 404 instead.
        """
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError(_CLASS_NOT_FOUND_MSG)

    async def find_history_id(
        self,
        session: AsyncSession,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> UUID | None:
        """Find the materialized history row for the gym-local day, if any.

        Matches the whole local day [00:00, next-00:00) in UTC so a per-occurrence
        time override still resolves to the same row. Public: this is the
        "is this occurrence materialized?" check ``ClassesExceptionsService``
        reuses (via its injected ``undo_service``) to decide whether a
        same-date override must also sync the history snapshot.
        """
        zone = ZoneInfo(gym_tz)
        day_start = datetime.combine(
            occurrence_date, time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        day_end = datetime.combine(
            occurrence_date + timedelta(days=1), time(0, 0), tzinfo=zone
        ).astimezone(UTC)
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "classes_undo_find_history.sql"),
            {
                "class_id": str(class_id),
                "start": day_start,
                "end": day_end,
            },
        )
        return row["class_history_id"] if row else None

    async def _find_all_attendee_members(
        self, session: AsyncSession, history_id: UUID
    ) -> list[UUID]:
        """Every member with attendance on the occurrence (incl. a no-membership
        attendee), for the per-member reverser loop. Includes the no-membership
        (NULL-attribution) attendee, who still earned points."""
        rows = await self._fetchall(
            session,
            load_sql(SQL_DIR / "classes_undo_all_attendee_members.sql"),
            {"class_history_id": str(history_id)},
        )
        return [row["member_id"] for row in rows]

    async def _load_points(self, session: AsyncSession, class_id: UUID) -> int:
        """The class's ``points_worth`` — the per-check-in award to claw back,
        loaded once per occurrence and passed to each reverser call."""
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "classes_load_one.sql"),
            {"class_id": str(class_id)},
        )
        return int(row["points_worth"]) if row else 0

    async def _delete_history(
        self,
        session: AsyncSession,
        history_id: UUID,
    ) -> None:
        """Delete the materialized occurrence (attendance already gone)."""
        await session.execute(
            text(load_sql(SQL_DIR / "classes_undo_delete_history.sql")),
            {"class_history_id": str(history_id)},
        )

    async def _upsert_cancelled_exception(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> None:
        """Write (or flip) the instance exception to cancelled for the date."""
        await session.execute(
            text(load_sql(SQL_DIR / "classes_undo_upsert_exception.sql")),
            {
                "class_id": str(class_id),
                "gym_id": str(gym_id),
                "original_date": occurrence_date,
            },
        )

    # -- reschedule ------------------------------------------------------

    async def reschedule_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        new_date: date,
    ) -> OccurrenceRescheduleResponse:
        """Move an occurrence to ``new_date`` (any date), attendance following.

        The occurrence keeps its currently-effective start time / duration /
        instructor (a bare move carries no override); a FUTURE target wipes
        its check-ins, a today / PAST target keeps them with the history
        snapshot synced onto the new instant — all in one transaction with the
        exception write. See the module docstring.

        Raises:
            ValueError: no real occurrence on ``occurrence_date`` (400); class
                missing (404, "not found").
            RescheduleConflictError: the exact target instant (new_date + start
                time) is already taken by a non-cancelled occurrence (409).
        """
        class_row = await self._load_class_in_gym(class_id, gym_id)
        gym_tz = await self._gym_timezone(gym_id)

        source = await self._occurrence_on(
            class_row, class_id, occurrence_date, gym_tz
        )
        if source is None:
            raise ValueError(
                f"No class occurrence on {occurrence_date} to reschedule"
            )

        effective_time = source.class_time
        new_occurred_at = datetime.combine(
            new_date, effective_time, tzinfo=ZoneInfo(gym_tz)
        ).astimezone(UTC)
        await self.assert_no_reschedule_conflict(
            class_row,
            class_id,
            occurrence_date,
            new_date,
            effective_time,
            new_occurred_at,
            gym_tz,
        )

        is_future = new_date > gym_today(gym_tz)
        try:
            async with self._db_pool.session() as session:
                await self.apply_reschedule_attendance(
                    session,
                    class_id,
                    gym_id,
                    occurrence_date,
                    new_occurred_at,
                    source.duration_minutes,
                    source.instructor_id,
                    is_future,
                    gym_tz,
                )
                row = (
                    (
                        await session.execute(
                            text(
                                load_sql(
                                    SQL_DIR
                                    / "classes_reschedule_upsert_exception.sql"
                                )
                            ),
                            {
                                "class_id": str(class_id),
                                "gym_id": str(gym_id),
                                "original_date": occurrence_date,
                                "new_date": new_date,
                            },
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise RescheduleConflictError(_REDATE_CONFLICT_MSG) from exc
        if not row:
            raise RuntimeError("Reschedule write did not return a row")
        return OccurrenceRescheduleResponse(
            exception_id=row["exception_id"],
            class_id=row["class_id"],
            original_date=row["original_date"],
            new_date=row["new_date"],
        )

    async def assert_no_reschedule_conflict(
        self,
        class_row: dict,
        class_id: UUID,
        original_date: date,
        new_date: date,
        effective_time: time,
        new_occurred_at: datetime,
        gym_tz: str,
    ) -> None:
        """Raise ``RescheduleConflictError`` (→ 409) when the exact target
        instant is already taken by a non-cancelled occurrence of this class.

        Time-aware: the rejection keys on the full ``occurred_at`` (date AND
        effective start time), so landing on a busy day at a DIFFERENT time is
        allowed. Two independent checks, both keyed on the instant:

        1. A direct query for another reschedule (a different ``original_date``)
           already targeting this ``(new_date, effective_time)`` — the collision
           the single-day expander can't see (it only visits the target date
           itself, keyed on ``original_date``).
        2. The expander over ``[new_date, new_date]``: a recurrence / override
           occurrence whose ``occurred_at`` equals ``new_occurred_at``.

        The single home of the time-aware rule — both reschedule entry points
        (this service's endpoint and the ``ClassesExceptionsService`` upsert)
        call it, so they can never diverge.
        """
        collisions = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_reschedule_collision.sql"),
            {
                "class_id": str(class_id),
                "new_date": new_date,
                "original_date": original_date,
                "class_time": class_row["class_time"],
                "effective_time": effective_time,
            },
        )
        if collisions:
            raise RescheduleConflictError(
                f"Another occurrence is already rescheduled to {new_date} at "
                f"{effective_time}."
            )

        occurrences = await self._expand_day(
            class_row, class_id, new_date, gym_tz
        )
        if any(occ.occurred_at == new_occurred_at for occ in occurrences):
            raise RescheduleConflictError(
                f"A class already occurs on {new_date} at {effective_time}; "
                f"cannot reschedule onto it."
            )

    async def apply_reschedule_attendance(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        original_date: date,
        new_occurred_at: datetime,
        new_duration_minutes: int,
        instructor_id: UUID | None,
        is_future: bool,
        gym_tz: str,
    ) -> UUID | None:
        """Move the moved occurrence's materialized attendance, in the caller's
        OPEN transaction (no commit here — the caller owns the txn so the
        exception write lands atomically with this).

        * ``is_future`` (new_date after today, gym-local): WIPE the occurrence's
          check-ins via the shared ``_wipe_occurrence`` teardown — the moved
          occurrence re-materializes fresh when the class is next attended.
        * today / past: KEEP the check-ins, its history snapshot synced onto
          ``new_occurred_at`` / ``new_duration_minutes`` / ``instructor_id`` via
          ``sync_history_snapshot``.

        A never-materialized occurrence (no ``class_history`` on
        ``original_date``) is a no-op. Returns the moved ``class_history_id`` (or
        None when nothing was materialized).
        """
        history_id = await self.find_history_id(
            session, class_id, original_date, gym_tz
        )
        if history_id is None:
            return None
        if is_future:
            await self._wipe_occurrence(session, history_id, gym_id, class_id)
        else:
            await self.sync_history_snapshot(
                session,
                history_id,
                new_occurred_at,
                new_duration_minutes,
                instructor_id,
            )
        return history_id

    async def _load_class_in_gym(self, class_id: UUID, gym_id: UUID) -> dict:
        """Load the class row, asserting it belongs to ``gym_id`` (else 404)."""
        async with self._db_pool.session() as session:
            row = await self._fetchone(
                session,
                load_sql(SQL_DIR / "classes_load_one.sql"),
                {"class_id": str(class_id)},
            )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return row

    async def _occurrence_on(
        self,
        class_row: dict,
        class_id: UUID,
        when: date,
        gym_tz: str,
    ) -> EffectiveOccurrence | None:
        """The real, non-cancelled occurrence that lands on ``when`` (or None).

        Carries the occurrence's effective time / duration so a bare move keeps
        the slot's current schedule.
        """
        occurrences = await self._expand_day(class_row, class_id, when, gym_tz)
        for occ in occurrences:
            if occ.effective_date == when:
                return occ
        return None

    async def _expand_day(
        self,
        class_row: dict,
        class_id: UUID,
        when: date,
        gym_tz: str,
    ) -> list:
        """Expand the class over the single day ``[when, when]``."""
        instances = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_exception_list.sql"),
            {"class_id": str(class_id), "start_date": when, "end_date": when},
        )
        ranges = await self._read_all(
            load_sql(SQL_DIR / "classes_range_exception_list.sql"),
            {"class_id": str(class_id), "start_date": when, "end_date": when},
        )
        return self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            when,
            when,
            gym_tz,
        )

    async def _gym_timezone(self, gym_id: UUID) -> str:
        """Read the gym's IANA timezone (its own session)."""
        async with self._db_pool.session() as session:
            return await get_gym_timezone(session, gym_id)

    # -- db helpers ------------------------------------------------------

    @staticmethod
    async def _fetchone(
        session: AsyncSession,
        sql: str,
        params: dict,
    ) -> dict | None:
        row = (await session.execute(text(sql), params)).mappings().fetchone()
        return dict(row) if row else None

    @staticmethod
    async def _fetchall(
        session: AsyncSession,
        sql: str,
        params: dict,
    ) -> list[dict]:
        rows = (await session.execute(text(sql), params)).mappings().all()
        return [dict(row) for row in rows]

    async def _read_all(self, sql: str, params: dict) -> list[dict]:
        async with self._db_pool.session() as session:
            return await self._fetchall(session, sql, params)
