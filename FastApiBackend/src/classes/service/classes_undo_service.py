"""Un-occur (cancel) and reschedule a single class occurrence — Phase 6.

This is billing-adjacent: ``cancel_occurrence`` deletes ``member_attendance``
and may clear an auto-end-on-depletion ``end_date`` on a trial / one_time pack.
It runs every step of a cancel inside ONE transaction so a partial cancel can
never strand the occurrence half-cleaned-up.

Two operations:

* ``cancel_occurrence`` — for a gym-local calendar day: find the materialized
  ``class_history`` row, delete its attendance, reverse the auto-end on any
  trial / one_time pack that drops back below its capacity, delete the history
  row, and write the cancelled instance exception so the day never
  re-materializes. When the occurrence was never materialized (no check-ins),
  only the cancelled exception is written. **Points are NEVER clawed back** —
  ``members.points_balance`` and ``member_activities`` are left untouched (a
  claw-back would also trip the ``points_balance >= 0`` CHECK).

* ``reschedule_occurrence`` — move a future occurrence to a later date by
  upserting the instance exception's ``new_date`` (no history / attendance
  touched). Rejects a move onto an already-occupied date, and refuses to move
  an occurrence that has already been materialized (cancel it first).

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

from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
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
from src.shared.gym_timezone import get_gym_timezone
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_BAD_RESCHEDULE_MSG = (
    "Invalid reschedule: check the target date is after the original and "
    "within the class's schedule."
)


class ClassesUndoService:
    """Cancel / un-occur and reschedule a single class occurrence.

    Args:
        db_pool: Injected database connection pool (writes run at service_role,
            which append-only RLS requires for the class_history /
            member_attendance deletes).
        expander: The canonical recurrence + exception expander (pure) — used to
            validate the source occurrence and the reschedule target.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander

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
            history_id = await self._find_history_id(
                session, class_id, occurrence_date, gym_tz
            )

            attendance_deleted = 0
            unended: list[UUID] = []
            if history_id is not None:
                attendees = await self._find_attendees(session, history_id)
                attendance_deleted = await self._delete_attendance(
                    session, history_id
                )
                unended = await self._reverse_auto_ends(session, attendees)
                await self._delete_history(session, history_id)

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

    async def _find_history_id(
        self,
        session: AsyncSession,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> UUID | None:
        """Find the materialized history row for the gym-local day, if any.

        Matches the whole local day [00:00, next-00:00) in UTC so a per-occurrence
        time override still resolves to the same row.
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

    async def _find_attendees(
        self,
        session: AsyncSession,
        history_id: UUID,
    ) -> list[dict]:
        """Memberships with attendance on the occurrence (pre-delete snapshot)."""
        return await self._fetchall(
            session,
            load_sql(SQL_DIR / "classes_undo_find_attendees.sql"),
            {"class_history_id": str(history_id)},
        )

    async def _delete_attendance(
        self,
        session: AsyncSession,
        history_id: UUID,
    ) -> int:
        """Delete every attendance row for the occurrence; return the count."""
        rows = await self._fetchall(
            session,
            load_sql(SQL_DIR / "classes_undo_delete_attendance.sql"),
            {"class_history_id": str(history_id)},
        )
        return len(rows)

    async def _reverse_auto_ends(
        self,
        session: AsyncSession,
        attendees: list[dict],
    ) -> list[UUID]:
        """Clear the auto-end ``end_date`` on every trial / one_time pack that the
        deletion dropped back below its capacity.

        Runs AFTER the attendance delete (so the recount reflects the un-occur).
        NEVER touches points — see the module docstring.
        """
        unended: list[UUID] = []
        seen: set[tuple[str, str]] = set()
        for att in attendees:
            item_id = att["item_id"]
            member_id = att["member_id"]
            key = (str(item_id), str(member_id))
            if key in seen:
                continue
            seen.add(key)
            if await self._should_clear_end_date(session, att):
                await self._clear_end_date(session, item_id, member_id)
                unended.append(item_id)
        return unended

    async def _should_clear_end_date(
        self,
        session: AsyncSession,
        att: dict,
    ) -> bool:
        """Whether this membership's end_date is an auto-end to reverse.

        A non-null end_date on a trial / one_time pack with a finite class_count
        that, after the delete, holds fewer attendances than its capacity
        (class_count * quantity) is treated as the auto-end-on-depletion.
        """
        if att["end_date"] is None:
            return False
        if att["class_count"] is None:
            # Time-based (duration) pack: no depletion auto-end exists, so its
            # end_date came from elsewhere — never reverse it.
            return False
        if PlanType(att["plan_type"]) not in (PlanType.trial, PlanType.one_time):
            return False
        remaining = await self._count_attendance(
            session, att["item_id"], att["member_id"]
        )
        capacity = int(att["class_count"]) * int(att["quantity"])
        return remaining < capacity

    async def _count_attendance(
        self,
        session: AsyncSession,
        item_id: UUID,
        member_id: UUID,
    ) -> int:
        """Total attendance still recorded against one membership (post-delete)."""
        row = await self._fetchone(
            session,
            load_sql(SQL_DIR / "classes_undo_count_attendance.sql"),
            {"item_id": str(item_id), "member_id": str(member_id)},
        )
        return int(row["attendance_count"]) if row else 0

    async def _clear_end_date(
        self,
        session: AsyncSession,
        item_id: UUID,
        member_id: UUID,
    ) -> None:
        """Clear the membership's end_date (un-end the auto-ended pack)."""
        await session.execute(
            text(load_sql(SQL_DIR / "classes_undo_reverse_membership_end.sql")),
            {"item_id": str(item_id), "member_id": str(member_id)},
        )

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
        """Move a future, not-yet-materialized occurrence to ``new_date``.

        Raises:
            ValueError: ``new_date`` not after ``occurrence_date`` / not a real
                occurrence (400); class missing (404, "not found"); already
                materialized or the target date is occupied (409, "already
                materialized" / "conflict").
        """
        if new_date <= occurrence_date:
            raise ValueError("new_date must be after the occurrence date")

        class_row = await self._load_class_in_gym(class_id, gym_id)
        gym_tz = await self._gym_timezone(gym_id)

        if not await self._occurs_on(class_row, class_id, occurrence_date, gym_tz):
            raise ValueError(
                f"No class occurrence on {occurrence_date} to reschedule"
            )
        if await self._is_materialized(class_id, occurrence_date, gym_tz):
            raise ValueError(
                "Occurrence already materialized; cancel it first."
            )
        await self._reject_new_date_collision(
            class_row, class_id, occurrence_date, new_date, gym_tz
        )

        row = await self._write_returning(
            load_sql(SQL_DIR / "classes_reschedule_upsert_exception.sql"),
            {
                "class_id": str(class_id),
                "gym_id": str(gym_id),
                "original_date": occurrence_date,
                "new_date": new_date,
            },
        )
        return OccurrenceRescheduleResponse(
            exception_id=row["exception_id"],
            class_id=row["class_id"],
            original_date=row["original_date"],
            new_date=row["new_date"],
        )

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

    async def _occurs_on(
        self,
        class_row: dict,
        class_id: UUID,
        when: date,
        gym_tz: str,
    ) -> bool:
        """Whether a real, non-cancelled occurrence lands on ``when``."""
        occurrences = await self._expand_day(class_row, class_id, when, gym_tz)
        return any(occ.effective_date == when for occ in occurrences)

    async def _is_materialized(
        self,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> bool:
        """Whether the occurrence already has a class_history row."""
        async with self._db_pool.session() as session:
            history_id = await self._find_history_id(
                session, class_id, occurrence_date, gym_tz
            )
        return history_id is not None

    async def _reject_new_date_collision(
        self,
        class_row: dict,
        class_id: UUID,
        occurrence_date: date,
        new_date: date,
        gym_tz: str,
    ) -> None:
        """Raise (conflict -> 409) if a non-cancelled occurrence already lands on
        ``new_date``.

        Two checks, mirroring the Phase-3 reschedule-conflict guard: a direct
        query for another reschedule already targeting ``new_date`` (reusing
        ``classes_instance_reschedule_collision.sql``), then the expander over
        ``[new_date, new_date]`` for a recurrence / override occurrence there.
        """
        collisions = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_reschedule_collision.sql"),
            {
                "class_id": str(class_id),
                "new_date": new_date,
                "original_date": occurrence_date,
            },
        )
        if collisions:
            raise ValueError(
                f"conflict: another occurrence is already rescheduled to "
                f"{new_date}."
            )

        occurrences = await self._expand_day(
            class_row, class_id, new_date, gym_tz
        )
        if any(occ.effective_date == new_date for occ in occurrences):
            raise ValueError(
                f"conflict: a class already occurs on {new_date}; cannot "
                f"reschedule onto it."
            )

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

    async def _write_returning(self, sql: str, params: dict) -> dict:
        """Run a write + return its single RETURNING row, mapping a constraint
        violation (bad date range / cross-gym class) to a 400."""
        try:
            async with self._db_pool.session() as session:
                row = (
                    (await session.execute(text(sql), params))
                    .mappings()
                    .fetchone()
                )
                await session.commit()
        except IntegrityError as exc:
            raise ValueError(_BAD_RESCHEDULE_MSG) from exc
        if not row:
            raise RuntimeError("Write did not return a row")
        return dict(row)
