"""Un-occur (cancel) and reschedule a single class occurrence.

An occurrence's identity is its ORIGINAL slot — ``(class_id, original_date,
original_time)``, the owning schedule version's pre-exception slot. Neither
operation ever re-keys anything: attendance and sign-ups stay keyed to the
original slot wherever the occurrence moves.

This is billing-adjacent: both operations reverse ``member_attendance`` via
the shared ``CheckinReverser`` (delete attendance + claw back points floored
at 0 + drop the activity + reverse the pack auto-end), a deliberate
``classes -> checkin`` dependency — the reverse of the usual one-way
``checkin -> classes`` seam — chosen so the reversal lives in exactly one
place. ``CheckinReverser`` imports nothing from ``src.classes``, so there is
no import cycle. Every step of an operation runs inside ONE transaction.

Two operations:

* ``cancel_occurrence`` — reverse the occurrence's check-ins (points clawed
  back), DELETE its sign-ups (a cancelled occurrence can't be attended, so
  its reservations are dead rows), and upsert the cancelled instance
  exception.

* ``reschedule_occurrence`` — move an occurrence to ``new_date`` (ANY date —
  past, today, or future; ``original_date`` is only the anchor) by upserting
  the instance exception's ``new_date``. Reservations (sign-ups) ALWAYS
  carry (the identity key is untouched). Attendance follows the move,
  decided by the new EFFECTIVE START INSTANT — never the calendar day: a
  target instant still ahead of now (including later TODAY) wipes the moved
  occurrence's check-ins (same reversal as cancel — the class hasn't
  happened at its new slot); a target instant already past keeps them, with
  their denormalized ``occurred_at`` re-synced onto the move's effective
  instant (``sync_attendance_occurred_at``) so the streak / cycle-count /
  last-class window SQL keeps reading the right instant. The move is
  rejected only when the exact target instant
  (new_date + effective start time) is already taken by a non-cancelled
  occurrence — landing on a busy day at a different time is allowed. The
  same ``assert_no_reschedule_conflict`` + ``apply_reschedule_attendance``
  engine backs the CRM's ``POST /exceptions/instance`` reschedule
  (``ClassesExceptionsService`` delegates to it), so the two entry points can
  never diverge.

All occurrence resolution goes through the class's schedule VERSIONS
(``load_versions`` + the pure ``ClassesVersionExpander``): the version owning
``original_date``'s slot supplies the defaults (time / duration / weekday
instructor) and the frozen timezone every instant is computed in.

Auto-end reversal — IMPORTANT, inexact by necessity: there is no stored link
recording that a membership's ``end_date`` came from an auto-end-on-depletion
(versus a manual end). The best available signal is the depletion recompute:
after deleting the un-occurred attendance, if a trial / one_time pack with a
non-null ``end_date`` is now below its pack capacity (class_count * quantity,
the same capacity the check-in's auto-end uses), the ``end_date`` is treated
as the auto-end and cleared. This CANNOT perfectly distinguish an auto-end
from a manual end on a pack that still has capacity left. It is deliberately
keyed on the recomputed capacity, NOT on ``occurrence_date == end_date``: a
retroactive check-in stamps ``end_date`` = the day it was written, not the
occurrence date, so a date match would miss it.
"""

from datetime import UTC, date, datetime, time
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.service.checkin_reverser import CheckinReverser
from src.classes import SQL_DIR
from src.classes.schema.classes_expander_schema import (
    EffectiveOccurrence,
    ExpanderScheduleVersion,
)
from src.classes.schema.classes_undo_schema import (
    OccurrenceCancelResponse,
    OccurrenceRescheduleResponse,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_instance,
    to_expander_range,
    to_expander_schedule,
)
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_CLASS_NOT_FOUND_MSG = "Class not found"
_REDATE_CONFLICT_MSG = (
    "conflict: the reschedule target instant is already taken."
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
            which the attendance / sign-up RLS requires).
        expander: The single-shape recurrence engine (pure) — used for the
            weekday-default instructor lookup.
        version_expander: The versioned expander (pure) — every occurrence
            resolution and ownership decision goes through it.
        reverser: The shared per-member check-in reverser (from the
            ``checkin`` domain) — the one implementation of the attendance
            reversal, looped per attendee.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        expander: ClassesExpander,
        version_expander: ClassesVersionExpander,
        reverser: CheckinReverser,
    ) -> None:
        self._db_pool = db_pool
        self._expander = expander
        self._version_expander = version_expander
        self._reverser = reverser

    # -- cancel / un-occur ----------------------------------------------

    async def cancel_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
    ) -> OccurrenceCancelResponse:
        """Un-occur one occurrence: reverse its attendance, delete its
        sign-ups, and write the cancelled exception — all in one transaction.

        ``(occurrence_date, occurrence_time)`` is the occurrence's ORIGINAL
        slot — with several slots per day legal, the pair names exactly one
        occurrence; a sibling slot on the same date is untouched.

        Raises:
            ValueError: If the class does not exist for this gym (mapped to
                404).
        """
        await self._load_class_in_gym(class_id, gym_id)

        async with self._db_pool.session() as session:
            attendance_deleted, signups_deleted, unended = (
                await self.teardown_occurrence(
                    session, class_id, gym_id, occurrence_date,
                    occurrence_time,
                )
            )
            await self._upsert_cancelled_exception(
                session, class_id, gym_id, occurrence_date, occurrence_time
            )
            await session.commit()

        return OccurrenceCancelResponse(
            class_id=class_id,
            gym_id=gym_id,
            occurrence_date=occurrence_date,
            occurrence_time=occurrence_time,
            attendance_rows_deleted=attendance_deleted,
            signups_deleted=signups_deleted,
            memberships_unended=unended,
        )

    async def teardown_occurrence(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        original_date: date,
        original_time: time,
    ) -> tuple[int, int, list[UUID]]:
        """The shared cancel teardown: reverse the occurrence's attendance
        (points clawed back) + delete its sign-ups, in the caller's OPEN
        transaction — scoped to the exact ``(original_date, original_time)``
        slot, never a whole day. Public because BOTH cancel entry points run
        it — this service's ``cancel_occurrence`` endpoint AND the exceptions
        service's ``is_cancelled=True`` override upsert (the path the CRM
        uses) — so a cancel behaves identically no matter which route it
        arrives by.

        Returns ``(attendance_rows_deleted, signups_deleted,
        memberships_unended)``.
        """
        attendance_deleted, unended = await self._reverse_attendance(
            session, class_id, gym_id, original_date, original_time
        )
        signups_deleted = await self._delete_signups(
            session, class_id, original_date, original_time
        )
        return attendance_deleted, signups_deleted, unended

    async def _reverse_attendance(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        original_date: date,
        original_time: time,
    ) -> tuple[int, list[UUID]]:
        """Reverse one occurrence's attendance — the shared, billing-adjacent
        teardown used by cancel AND a FUTURE reschedule.

        Loads the class's ``points_worth`` ONCE, enumerates every attendee,
        then loops the shared ``CheckinReverser`` per attendee. Runs in the
        caller's transaction.

        Doing the auto-end reversal per member (delete A's attendance →
        recompute A's pack → reverse if below, then B…) is equivalent to the
        whole-occurrence recompute: each member's pack is independent — the
        depletion recount filters on that member's own ``item_id`` +
        ``member_id``, so B's delete never changes A's count.

        Returns ``(attendance_rows_deleted, memberships_unended)``.
        """
        points_worth = await self._load_points(session, class_id)
        members = await self._attendee_members(
            session, class_id, original_date, original_time
        )
        attendance_deleted = 0
        unended: list[UUID] = []
        for member_id in members:
            result = await self._reverser.reverse(
                session,
                member_id,
                gym_id,
                class_id,
                original_date,
                original_time,
                points_worth,
            )
            if result.removed:
                attendance_deleted += 1
            if result.membership_unended is not None:
                unended.append(result.membership_unended)
        return attendance_deleted, unended

    # -- reschedule ------------------------------------------------------

    async def reschedule_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
        new_date: date,
    ) -> OccurrenceRescheduleResponse:
        """Move an occurrence to ``new_date`` (any date), attendance following
        and sign-ups carrying (the identity key never changes).

        ``(occurrence_date, occurrence_time)`` is the ORIGINAL slot being
        moved. The occurrence keeps its currently-effective start time /
        duration (a bare move carries no override). See the module docstring.

        Raises:
            ValueError: no real occurrence at that slot (400); class missing
                (404, "not found").
            RescheduleConflictError: the exact target instant (new_date +
                start time) is already taken by a non-cancelled occurrence
                (409).
        """
        await self._load_class_in_gym(class_id, gym_id)
        versions = await self.load_versions(class_id)
        resolution = await self._resolve_occurrence(
            class_id, versions, occurrence_date, occurrence_time
        )
        if resolution is None:
            raise ValueError(
                f"No class occurrence on {occurrence_date} at "
                f"{occurrence_time} to reschedule"
            )
        owning, exception_row = resolution

        effective_time = self._effective_time(
            occurrence_time, exception_row
        )
        new_occurred_at = datetime.combine(
            new_date, effective_time, tzinfo=ZoneInfo(owning.timezone)
        ).astimezone(UTC)
        await self.assert_no_reschedule_conflict(
            class_id,
            versions,
            occurrence_date,
            occurrence_time,
            new_date,
            effective_time,
            new_occurred_at,
        )

        landing_unchanged = self.is_landing_unchanged(
            owning,
            exception_row,
            occurrence_date,
            occurrence_time,
            new_date,
            new_occurred_at,
        )
        # INSTANT-based, never day-based: a move to later TODAY is still a
        # move to a class that hasn't happened — its check-ins must wipe.
        is_future = new_occurred_at > datetime.now(UTC)
        try:
            async with self._db_pool.session() as session:
                if not landing_unchanged:
                    await self.apply_reschedule_attendance(
                        session,
                        class_id,
                        gym_id,
                        occurrence_date,
                        occurrence_time,
                        new_occurred_at,
                        is_future,
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
                                "original_time": occurrence_time,
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
            original_time=row["original_time"],
            new_date=row["new_date"],
        )

    async def assert_no_reschedule_conflict(
        self,
        class_id: UUID,
        versions: list[ExpanderScheduleVersion],
        original_date: date,
        original_time: time,
        new_date: date,
        effective_time: time,
        new_occurred_at: datetime,
    ) -> None:
        """Raise ``RescheduleConflictError`` (→ 409) when the exact target
        instant is already taken by a non-cancelled occurrence of this class.

        Time-aware: the rejection keys on the full target instant (date AND
        effective start time), so landing on a busy day at a DIFFERENT time
        is allowed. Two independent checks:

        1. Another reschedule (a different ORIGINAL SLOT — the SQL excludes
           the moved slot by its full ``(original_date, original_time)``
           pair, so a sibling same-date slot is a genuine candidate) already
           targeting ``new_date``. Each candidate's effective time is its own
           ``new_class_time`` when set, else its own ``original_time`` (the
           slot the exception is bound to); it collides only when the times
           match.
        2. The version expansion over ``[new_date, new_date]``: a recurrence /
           override occurrence whose ``occurred_at`` equals the target
           instant.

        The single home of the time-aware rule — both reschedule entry points
        (this service's endpoint and the ``ClassesExceptionsService`` upsert)
        call it, so they can never diverge.
        """
        candidates = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_reschedule_collision.sql"),
            {
                "class_id": str(class_id),
                "new_date": new_date,
                "original_date": original_date,
                "original_time": original_time,
            },
        )
        for row in candidates:
            candidate_time = (
                row["new_class_time"]
                if row["new_class_time"] is not None
                else row["original_time"]
            )
            if candidate_time == effective_time:
                raise RescheduleConflictError(
                    f"Another occurrence is already rescheduled to "
                    f"{new_date} at {effective_time}."
                )

        occurrences = await self._expand_day(class_id, versions, new_date)
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
        original_time: time,
        new_occurred_at: datetime,
        is_future: bool,
    ) -> None:
        """Handle the moved occurrence's attendance, in the caller's OPEN
        transaction (no commit here — the caller owns the txn so the
        exception write lands atomically with this).

        * ``is_future`` (the new EFFECTIVE start instant is still ahead of
          now — includes a move to later today): WIPE the occurrence's
          check-ins (the shared reversal, points clawed back). Reservations
          are NOT touched — they always carry.
        * an already-past target instant: KEEP the check-ins, their
          denormalized ``occurred_at`` re-synced onto the move's effective
          instant (a no-op when nobody attended).
        """
        if is_future:
            await self._reverse_attendance(
                session, class_id, gym_id, original_date, original_time
            )
        else:
            await self.sync_attendance_occurred_at(
                session, class_id, original_date, original_time,
                new_occurred_at,
            )

    async def sync_attendance_occurred_at(
        self,
        session: AsyncSession,
        class_id: UUID,
        original_date: date,
        original_time: time,
        occurred_at: datetime,
    ) -> None:
        """Re-sync the denormalized effective start instant on a KEPT
        occurrence's attendance rows (identity key unchanged) — scoped to the
        exact slot, so a same-day sibling occurrence's rows are never
        touched. Public: ``ClassesExceptionsService`` calls this for a
        same-slot override on an attended occurrence, in the SAME transaction
        as its exception write. A no-op when the occurrence has no
        attendance."""
        await session.execute(
            text(
                load_sql(SQL_DIR / "classes_attendance_occurred_at_sync.sql")
            ),
            {
                "class_id": str(class_id),
                "original_date": original_date,
                "original_time": original_time,
                "occurred_at": occurred_at,
            },
        )

    # -- occurrence resolution (shared with the exceptions service) -------

    async def load_versions(
        self, class_id: UUID
    ) -> list[ExpanderScheduleVersion]:
        """ALL of the class's schedule versions, oldest first."""
        rows = await self._read_all(
            load_sql(SQL_DIR / "classes_schedules_for_class.sql"),
            {"class_id": str(class_id)},
        )
        return [to_expander_schedule(row) for row in rows]

    def owning_slots(
        self,
        versions: list[ExpanderScheduleVersion],
        when: date,
    ) -> list[tuple[ExpanderScheduleVersion, EffectiveOccurrence]]:
        """ALL of ``when``'s owned bare slots (+ their owning versions),
        exceptions NOT applied — pure ownership. A multi-slot day returns one
        entry per slot. Public: the range-cancel teardown iterates every slot
        of a covered date, using each bare occurrence's ``occurred_at`` as
        that slot's effective start instant (with no instance exception in
        play, a range never changes the time, so the pure owning slot IS the
        effective instant)."""
        occurrences = self._version_expander.expand(
            versions, [], [], when, when
        )
        return [
            (
                next(
                    v for v in versions if v.schedule_id == occ.schedule_id
                ),
                occ,
            )
            for occ in occurrences
            if occ.original_date == when
        ]

    def owning_slot(
        self,
        versions: list[ExpanderScheduleVersion],
        when: date,
        slot_time: time,
    ) -> tuple[ExpanderScheduleVersion, EffectiveOccurrence] | None:
        """The exact ``(when, slot_time)`` owned bare slot (+ its owning
        version), or None when no version's recurrence emits it."""
        return next(
            (
                (version, occ)
                for version, occ in self.owning_slots(versions, when)
                if occ.original_time == slot_time
            ),
            None,
        )

    async def owning_version(
        self, class_id: UUID, when: date, slot_time: time
    ) -> ExpanderScheduleVersion | None:
        """The schedule version owning the ``(when, slot_time)`` slot for
        this class, or None when the recurrence doesn't emit it. Public: the
        exceptions service resolves override fallbacks (duration / slot
        instructor) against the OWNING version — a retro edit on an
        old-version slot falls back to THAT version's defaults, never the
        current one's."""
        versions = await self.load_versions(class_id)
        slot = self.owning_slot(versions, when, slot_time)
        return slot[0] if slot is not None else None

    async def _resolve_occurrence(
        self,
        class_id: UUID,
        versions: list[ExpanderScheduleVersion],
        original_date: date,
        original_time: time,
    ) -> tuple[ExpanderScheduleVersion, dict | None] | None:
        """The owning version + any existing exception row for the exact
        slot, or None when the recurrence doesn't emit it / the occurrence is
        cancelled."""
        slot = self.owning_slot(versions, original_date, original_time)
        if slot is None:
            return None
        exception_row = await self.exception_on(
            class_id, original_date, original_time
        )
        if exception_row is not None and exception_row["is_cancelled"]:
            return None
        return slot[0], exception_row

    def resolve_default_instructor(
        self,
        version: ExpanderScheduleVersion,
        when: date,
        slot_time: time,
    ) -> UUID | None:
        """The owning version's default instructor for the ``(when,
        slot_time)`` slot, ignoring any per-occurrence override.

        Pure (no I/O) — the fallback a full-replace override upsert or
        reschedule uses when the request omits ``new_instructor_id``.
        Delegates to the expander's own slot-default resolution
        (``ClassesExpander.instructor_for``) so this can never drift from the
        expander's read-path semantics.
        """
        return self._expander.instructor_for(version, when, slot_time)

    @staticmethod
    def _effective_time(
        original_time: time, exception_row: dict | None
    ) -> time:
        """The occurrence's currently-effective start time — the override
        when set, else the occurrence's own original slot time (the caller
        supplies it; the exception row it came from stores the same value)."""
        if (
            exception_row is not None
            and exception_row["new_class_time"] is not None
        ):
            return exception_row["new_class_time"]
        return original_time

    async def _expand_day(
        self,
        class_id: UUID,
        versions: list[ExpanderScheduleVersion],
        when: date,
        session: AsyncSession | None = None,
    ) -> list[EffectiveOccurrence]:
        """Expand the class over the single day ``[when, when]`` with its
        exceptions applied. ``session``, when given, runs both reads on the
        CALLER's open transaction — so an uncommitted write earlier in that
        same transaction (e.g. a just-inserted range exception) is visible;
        omitted, each read opens its own short-lived session (the default,
        read-only-elsewhere usage)."""
        instances = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_exception_list.sql"),
            {"class_id": str(class_id), "start_date": when, "end_date": when},
            session=session,
        )
        ranges = await self._read_all(
            load_sql(SQL_DIR / "classes_range_exception_list.sql"),
            {"class_id": str(class_id), "start_date": when, "end_date": when},
            session=session,
        )
        return self._version_expander.expand(
            versions,
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            when,
            when,
        )

    async def expand_day(
        self,
        session: AsyncSession,
        class_id: UUID,
        versions: list[ExpanderScheduleVersion],
        when: date,
    ) -> list[EffectiveOccurrence]:
        """Public seam onto ``_expand_day``, session REQUIRED: expand one
        day inside the CALLER's open transaction so an uncommitted write in
        that same transaction is visible. Used by the range-cancel teardown
        (``ClassesExceptionsService``) to resolve a covered date THROUGH the
        just-inserted range — the same instance-wins-over-range /
        earliest-created-range-wins precedence every other read uses,
        without duplicating the expansion logic."""
        return await self._expand_day(class_id, versions, when, session=session)

    async def exception_on(
        self,
        class_id: UUID,
        when: date,
        slot_time: time,
        session: AsyncSession | None = None,
    ) -> dict | None:
        """The instance-exception row bound to the exact ``(when,
        slot_time)`` slot, if any — several exception rows per date are legal
        now, so the read filters on the full slot key. Public: the exceptions
        service reads it to detect a no-op re-send of an existing reschedule
        (the CRM preserves a move by re-sending its target), and the
        range-cancel teardown reads it (on the caller's open session) to
        confirm no instance exception governs a candidate slot instead of
        the range. ``session``, when given, runs on the CALLER's open
        transaction."""
        rows = await self._read_all(
            load_sql(SQL_DIR / "classes_instance_exception_list.sql"),
            {"class_id": str(class_id), "start_date": when, "end_date": when},
            session=session,
        )
        return next(
            (row for row in rows if row["original_time"] == slot_time),
            None,
        )

    def is_landing_unchanged(
        self,
        owning: ExpanderScheduleVersion,
        exception_row: dict | None,
        original_date: date,
        original_time: time,
        new_date: date,
        new_occurred_at: datetime,
    ) -> bool:
        """Whether a reschedule request targets the occurrence's CURRENT
        effective landing (same date, same instant). A no-op move must not
        re-run the attendance handling — a future-target wipe would reverse
        early check-ins on a save that changed nothing about the slot (the
        CRM re-sends the existing target to preserve a move across an
        override edit)."""
        current_date = (
            exception_row["new_date"] or original_date
            if exception_row is not None
            else original_date
        )
        current_instant = datetime.combine(
            current_date,
            self._effective_time(original_time, exception_row),
            tzinfo=ZoneInfo(owning.timezone),
        ).astimezone(UTC)
        return new_date == current_date and new_occurred_at == current_instant

    # -- row plumbing ------------------------------------------------------

    async def _load_class_in_gym(self, class_id: UUID, gym_id: UUID) -> dict:
        """Load the class identity row, asserting it belongs to ``gym_id``
        (else 404)."""
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "classes_load_one.sql")),
                        {"class_id": str(class_id)},
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise ValueError(_CLASS_NOT_FOUND_MSG)
        return dict(row)

    async def _attendee_members(
        self,
        session: AsyncSession,
        class_id: UUID,
        original_date: date,
        original_time: time,
    ) -> list[UUID]:
        """Every member with attendance on the exact occurrence slot (incl. a
        no-membership attendee, who still earned points)."""
        rows = (
            (
                await session.execute(
                    text(
                        load_sql(
                            SQL_DIR / "classes_undo_all_attendee_members.sql"
                        )
                    ),
                    {
                        "class_id": str(class_id),
                        "original_date": original_date,
                        "original_time": original_time,
                    },
                )
            )
            .mappings()
            .all()
        )
        return [row["member_id"] for row in rows]

    async def _load_points(
        self, session: AsyncSession, class_id: UUID
    ) -> int:
        """The class's ``points_worth`` — the per-check-in award to claw back,
        loaded once per occurrence and passed to each reverser call."""
        row = (
            (
                await session.execute(
                    text(load_sql(SQL_DIR / "classes_load_one.sql")),
                    {"class_id": str(class_id)},
                )
            )
            .mappings()
            .fetchone()
        )
        return int(row["points_worth"]) if row else 0

    async def _delete_signups(
        self,
        session: AsyncSession,
        class_id: UUID,
        original_date: date,
        original_time: time,
    ) -> int:
        """Delete the exact occurrence slot's sign-ups; returns how many
        were removed."""
        result = await session.execute(
            text(
                load_sql(
                    SQL_DIR / "classes_signups_delete_for_occurrence.sql"
                )
            ),
            {
                "class_id": str(class_id),
                "original_date": original_date,
                "original_time": original_time,
            },
        )
        return result.rowcount or 0

    async def _upsert_cancelled_exception(
        self,
        session: AsyncSession,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
        occurrence_time: time,
    ) -> None:
        """Write (or flip) the slot's instance exception to cancelled."""
        await session.execute(
            text(load_sql(SQL_DIR / "classes_undo_upsert_exception.sql")),
            {
                "class_id": str(class_id),
                "gym_id": str(gym_id),
                "original_date": occurrence_date,
                "original_time": occurrence_time,
            },
        )

    async def _read_all(
        self,
        sql: str,
        params: dict,
        session: AsyncSession | None = None,
    ) -> list[dict]:
        """Run a read; ``session`` given runs it on the caller's OPEN
        transaction (so an uncommitted write earlier in that transaction is
        visible), omitted opens a short-lived session of its own."""
        if session is not None:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
            return [dict(row) for row in rows]
        async with self._db_pool.session() as owned_session:
            rows = (
                (await owned_session.execute(text(sql), params))
                .mappings()
                .all()
            )
        return [dict(row) for row in rows]
