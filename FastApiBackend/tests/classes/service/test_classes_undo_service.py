"""Unit tests for ``ClassesUndoService`` — cancel + reschedule, keyed on the
occurrence's full identity slot ``(class_id, original_date, original_time)``.

``db_pool``/``session`` and the ``CheckinReverser`` are mocked; the recurrence
engines (``ClassesExpander`` + ``ClassesVersionExpander``) are REAL, so
ownership / collision resolution is exercised for real. Individual SQL-hitting
private methods (``_load_class_in_gym``, ``_load_points``,
``_attendee_members``, ``_delete_signups``, ``_upsert_cancelled_exception``,
``_exception_on`` via ``_read_all``) are stubbed per test — the DB boundary —
while the orchestration logic that calls them runs for real.

Coverage:
* the time-aware reschedule collision check (``assert_no_reschedule_conflict``)
  — same instant rejected, same date different time allowed, a candidate
  reschedule collision resolved against EACH candidate's own owning version
  (not a fixed/current version), a move onto a SIBLING slot's exact natural
  instant rejected, and the self-exclusion excluding only the MOVED slot (a
  same-date sibling exception is a genuine collision candidate, not excluded);
* ``teardown_occurrence`` (the shared cancel teardown BOTH cancel entry points
  — this service's ``cancel_occurrence`` AND the exceptions service's
  ``is_cancelled=True`` override — and the version-mint wipe route through) —
  reverses attendance, deletes sign-ups, and returns the combined counts, all
  scoped to the exact ``(date, time)`` slot passed through untouched;
* cancel reverses attendance (via the real ``_reverse_attendance`` loop over
  the mocked reverser), deletes sign-ups, and writes the cancelled exception —
  scoped to ONE slot, a same-date sibling slot's calls are never made;
* ``exception_on`` (the public single-slot exception lookup the exceptions
  service also reads to detect a no-op reschedule re-send);
* ``apply_reschedule_attendance``'s branch — a FUTURE target wipes attendance,
  a today/past target re-syncs ``occurred_at`` instead (scoped to the slot) —
  both directly and via the full ``reschedule_occurrence`` orchestration;
* a reschedule re-send of the occurrence's CURRENT effective landing (a
  no-op move) skips the attendance handling entirely but still (re)writes
  the exception row.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import UTC, date, datetime, time
from unittest.mock import ANY, AsyncMock, MagicMock
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import CheckinRemoveResponse
from src.classes.schema.classes_expander_schema import (
    ALL_DAYS_KEY,
    ClassSlot,
    ExpanderScheduleVersion,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_undo_service import (
    ClassesUndoService,
    RescheduleConflictError,
)
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)

CHICAGO = "America/Chicago"
_FAR_PAST = datetime(2020, 1, 1, tzinfo=UTC)
_FAR_FUTURE_DATE = date(2099, 1, 1)
_FAR_PAST_DATE = date(2000, 1, 1)
_SLOT_TIME = time(9, 0)


def _version(
    *,
    effective_from: datetime,
    class_id: UUID | None = None,
    timezone: str = CHICAGO,
    class_time: time = time(9, 0),
    start_date: date = date(2020, 1, 1),
    end_date: date | None = None,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
) -> ExpanderScheduleVersion:
    """A single-slot-per-day schedule version (daily recurrence, unless
    overridden)."""
    return ExpanderScheduleVersion(
        schedule_id=uuid4(),
        class_id=class_id or uuid4(),
        gym_id=uuid4(),
        effective_from=effective_from,
        timezone=timezone,
        duration_minutes=60,
        recurring_unit=recurring_unit,
        recurring_interval=1,
        weekday_slots={ALL_DAYS_KEY: [ClassSlot(time=class_time)]},
        start_date=start_date,
        end_date=end_date,
    )


def _multi_slot_version(
    *,
    effective_from: datetime,
    class_id: UUID | None = None,
    timezone: str = CHICAGO,
    times: Iterable[time] = (time(6, 0), time(18, 0)),
    start_date: date = date(2020, 1, 1),
    end_date: date | None = None,
) -> ExpanderScheduleVersion:
    """A daily-recurring version with SEVERAL slots per date — needed for the
    sibling-slot reschedule-collision cases."""
    return ExpanderScheduleVersion(
        schedule_id=uuid4(),
        class_id=class_id or uuid4(),
        gym_id=uuid4(),
        effective_from=effective_from,
        timezone=timezone,
        duration_minutes=60,
        recurring_unit=RecurringUnit.daily,
        recurring_interval=1,
        weekday_slots={ALL_DAYS_KEY: [ClassSlot(time=t) for t in times]},
        start_date=start_date,
        end_date=end_date,
    )


def _occurred_at(when: date, at: time, tz: str = CHICAGO) -> datetime:
    return datetime.combine(when, at, tzinfo=ZoneInfo(tz)).astimezone(UTC)


def _fake_db_pool(row: dict | None = None) -> MagicMock:
    """A ``db_pool`` double whose ``session()`` is an async context manager.

    When ``row`` is given, ``session.execute(...).mappings().fetchone()``
    returns it (the reschedule upsert's ``RETURNING`` row); otherwise the
    execute return is an inert MagicMock (used only when every SQL-hitting
    call is separately stubbed).
    """
    pool = MagicMock()
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.commit = AsyncMock()
    if row is not None:
        result = MagicMock()
        result.mappings.return_value.fetchone.return_value = row
        session.execute = AsyncMock(return_value=result)
    pool.session.return_value = session
    return pool


def _service(
    *, db_pool: MagicMock | None = None, reverser: AsyncMock | None = None
) -> ClassesUndoService:
    return ClassesUndoService(
        db_pool=db_pool or _fake_db_pool(),
        expander=ClassesExpander(),
        version_expander=ClassesVersionExpander(ClassesExpander()),
        reverser=reverser or AsyncMock(),
    )


# -- the time-aware reschedule collision check ----------------------------


class TestRescheduleConflict:
    """``assert_no_reschedule_conflict`` — DB reads (``_read_all`` /
    ``_expand_day``) are stubbed per case; ownership/expansion is real."""

    def _stub_reads(
        self,
        svc: ClassesUndoService,
        *,
        collision_rows: list[dict] | None = None,
        instance_rows: list[dict] | None = None,
        range_rows: list[dict] | None = None,
    ) -> None:
        async def _read_all(
            sql: str, params: dict, session: object | None = None
        ) -> list[dict]:
            # The collision query is the only one with an inequality
            # (excludes the moved slot's own (original_date, original_time)).
            if "<>" in sql:
                return list(collision_rows or [])
            if "class_range_exceptions" in sql:
                return list(range_rows or [])
            return list(instance_rows or [])

        svc._read_all = _read_all  # type: ignore[method-assign]

    async def test_same_instant_rejected(self) -> None:
        """A move onto a day that already has a natural occurrence at the
        SAME time is a conflict (the exact target instant is taken)."""
        svc = _service()
        v1 = _version(effective_from=_FAR_PAST)
        self._stub_reads(svc)
        target = date(2025, 8, 1)

        with pytest.raises(RescheduleConflictError, match="already occurs"):
            await svc.assert_no_reschedule_conflict(
                v1.class_id,
                [v1],
                original_date=date(2025, 7, 1),
                original_time=_SLOT_TIME,
                new_date=target,
                effective_time=time(9, 0),
                new_occurred_at=_occurred_at(target, time(9, 0)),
            )

    async def test_allowed_when_same_date_different_time(self) -> None:
        """A move onto a busy day at a DIFFERENT time is allowed."""
        svc = _service()
        v1 = _version(effective_from=_FAR_PAST)
        self._stub_reads(svc)
        target = date(2025, 8, 1)

        await svc.assert_no_reschedule_conflict(
            v1.class_id,
            [v1],
            original_date=date(2025, 7, 1),
            original_time=_SLOT_TIME,
            new_date=target,
            effective_time=time(10, 0),
            new_occurred_at=_occurred_at(target, time(10, 0)),
        )

    async def test_candidate_collision_resolved_per_candidates_own_version(
        self,
    ) -> None:
        """Two candidates already rescheduled onto the same ``new_date``, one
        from a v1-owned original date (explicit override time) and one from a
        v2-owned original date (no override -> falls back to v2's OWN
        class_time, never v1's). The natural-occurrence check is neutralized
        (``_expand_day`` stubbed empty) so only the candidate loop is under
        test."""
        class_id = uuid4()
        mint = datetime(2025, 1, 1, tzinfo=UTC)
        v1 = _version(class_id=class_id, effective_from=_FAR_PAST)
        v2 = _version(
            class_id=class_id, effective_from=mint, class_time=time(19, 0)
        )
        target = date(2025, 8, 15)
        candidate_v1 = {
            "exception_id": uuid4(),
            "original_date": date(2024, 2, 1),  # owned by v1 (before mint)
            "original_time": _SLOT_TIME,
            "new_date": target,
            "new_class_time": time(14, 0),  # explicit override
        }
        candidate_v2 = {
            "exception_id": uuid4(),
            "original_date": date(2025, 7, 1),  # owned by v2 (after mint)
            "original_time": time(19, 0),
            "new_date": target,
            "new_class_time": None,  # falls back to the OWNING version's time
        }
        svc = _service()
        self._stub_reads(
            svc, collision_rows=[candidate_v1, candidate_v2]
        )
        svc._expand_day = AsyncMock(return_value=[])  # type: ignore[method-assign]

        async def _check(effective_time: time) -> None:
            await svc.assert_no_reschedule_conflict(
                class_id,
                [v1, v2],
                original_date=date(2025, 6, 1),
                original_time=_SLOT_TIME,
                new_date=target,
                effective_time=effective_time,
                new_occurred_at=_occurred_at(target, effective_time),
            )

        # Matches candidate_v1's explicit 14:00 override.
        with pytest.raises(RescheduleConflictError, match="already rescheduled"):
            await _check(time(14, 0))

        # Matches candidate_v2's fallback to v2's OWN class_time (19:00) —
        # proves the resolution used v2, not v1.
        with pytest.raises(RescheduleConflictError, match="already rescheduled"):
            await _check(time(19, 0))

        # v1's class_time (09:00) matches NEITHER candidate: candidate_v1 has
        # an explicit 14:00 override (v1's own default is irrelevant here),
        # and candidate_v2 resolves against v2 (19:00), not v1. No conflict.
        await _check(time(9, 0))

    async def test_reschedule_onto_sibling_slots_natural_instant_conflicts(
        self,
    ) -> None:
        """Moving (date, 06:00) onto a target date's SIBLING natural instant
        (18:00, on a class with two slots per day) is a conflict — landing on
        the target's OWN 06:00 time (unoccupied by either slot) is fine."""
        svc = _service()
        v1 = _multi_slot_version(effective_from=_FAR_PAST)
        self._stub_reads(svc)  # no existing exceptions in play
        origin = date(2025, 7, 1)
        target = date(2025, 9, 1)

        with pytest.raises(RescheduleConflictError, match="already occurs"):
            await svc.assert_no_reschedule_conflict(
                v1.class_id,
                [v1],
                original_date=origin,
                original_time=time(6, 0),
                new_date=target,
                effective_time=time(18, 0),
                new_occurred_at=_occurred_at(target, time(18, 0)),
            )

        # A free time on the target date (neither slot occupies it) is fine.
        await svc.assert_no_reschedule_conflict(
            v1.class_id,
            [v1],
            original_date=origin,
            original_time=time(6, 0),
            new_date=target,
            effective_time=time(12, 0),
            new_occurred_at=_occurred_at(target, time(12, 0)),
        )

    async def test_self_exclusion_excludes_only_the_moved_slot(self) -> None:
        """The candidate-collision self-exclusion is keyed on the FULL
        ``(original_date, original_time)`` pair — a sibling exception bound
        to the SAME original_date but a DIFFERENT original_time is a genuine
        collision candidate, never excluded just because the date matches."""
        svc = _service()
        v1 = _multi_slot_version(effective_from=_FAR_PAST)
        origin = date(2025, 7, 1)
        target = date(2025, 9, 1)
        sibling_candidate = {
            "exception_id": uuid4(),
            "original_date": origin,  # SAME original_date as the moved slot
            "original_time": time(18, 0),  # DIFFERENT original_time
            "new_date": target,
            "new_class_time": time(9, 0),
        }
        self._stub_reads(svc, collision_rows=[sibling_candidate])
        svc._expand_day = AsyncMock(return_value=[])  # type: ignore[method-assign]

        # The sibling's already-claimed 09:00 target collides.
        with pytest.raises(RescheduleConflictError, match="already rescheduled"):
            await svc.assert_no_reschedule_conflict(
                v1.class_id,
                [v1],
                original_date=origin,
                original_time=time(6, 0),
                new_date=target,
                effective_time=time(9, 0),
                new_occurred_at=_occurred_at(target, time(9, 0)),
            )
        # A different target time the sibling doesn't occupy is fine.
        await svc.assert_no_reschedule_conflict(
            v1.class_id,
            [v1],
            original_date=origin,
            original_time=time(6, 0),
            new_date=target,
            effective_time=time(10, 0),
            new_occurred_at=_occurred_at(target, time(10, 0)),
        )


# -- teardown_occurrence (the shared cancel teardown) ------------------------


class TestTeardownOccurrence:
    """``teardown_occurrence`` is the extracted shared teardown — BOTH cancel
    entry points (this service's ``cancel_occurrence`` and the exceptions
    service's ``is_cancelled=True`` override upsert) and the version-mint
    wipe (``ClassesVersionsService``) call it directly, so a cancel/wipe
    behaves identically no matter which route it arrives by."""

    async def test_reverses_attendance_and_deletes_signups(self) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 1)
        occurrence_time = time(6, 0)
        member_a, member_b = uuid4(), uuid4()
        points_worth = 40
        unended_item = uuid4()

        reverser = AsyncMock()
        reverser.reverse.side_effect = [
            CheckinRemoveResponse(
                removed=True, points_reverted=points_worth
            ),
            CheckinRemoveResponse(
                removed=True,
                points_reverted=points_worth,
                membership_unended=unended_item,
            ),
        ]
        svc = _service(reverser=reverser)
        svc._load_points = AsyncMock(return_value=points_worth)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(  # type: ignore[method-assign]
            return_value=[member_a, member_b]
        )
        svc._delete_signups = AsyncMock(return_value=2)  # type: ignore[method-assign]
        session = object()

        (
            attendance_deleted,
            signups_deleted,
            unended,
        ) = await svc.teardown_occurrence(
            session, class_id, gym_id, occurrence_date, occurrence_time
        )

        assert attendance_deleted == 2
        assert signups_deleted == 2
        assert unended == [unended_item]
        svc._delete_signups.assert_awaited_once_with(
            session, class_id, occurrence_date, occurrence_time
        )
        svc._attendee_members.assert_awaited_once_with(
            session, class_id, occurrence_date, occurrence_time
        )
        assert reverser.reverse.await_count == 2

    async def test_no_attendees_still_deletes_signups(self) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 2)
        occurrence_time = time(18, 0)

        svc = _service()
        svc._load_points = AsyncMock(return_value=50)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc._delete_signups = AsyncMock(return_value=1)  # type: ignore[method-assign]

        (
            attendance_deleted,
            signups_deleted,
            unended,
        ) = await svc.teardown_occurrence(
            object(), class_id, gym_id, occurrence_date, occurrence_time
        )

        assert attendance_deleted == 0
        assert signups_deleted == 1
        assert unended == []

    async def test_scoped_to_the_exact_slot_a_sibling_time_is_never_queried(
        self,
    ) -> None:
        """A same-day sibling slot (a DIFFERENT occurrence_time) is never
        touched: teardown forwards the EXACT occurrence_time it was given to
        both the attendee lookup and the sign-up delete, which the real SQL
        (``classes_undo_all_attendee_members.sql`` /
        ``classes_signups_delete_for_occurrence.sql``) filters on — so a
        06:00 cancel can never reach an 18:00 row."""
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 3)
        cancelled_time = time(6, 0)
        sibling_time = time(18, 0)

        svc = _service()
        svc._load_points = AsyncMock(return_value=10)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc._delete_signups = AsyncMock(return_value=0)  # type: ignore[method-assign]

        await svc.teardown_occurrence(
            object(), class_id, gym_id, occurrence_date, cancelled_time
        )

        called_time = svc._attendee_members.await_args.args[3]
        assert called_time == cancelled_time
        assert called_time != sibling_time
        assert svc._delete_signups.await_args.args[3] == cancelled_time


# -- exception_on -------------------------------------------------------


class TestExceptionOn:
    """The public single-slot exception lookup — the exceptions service
    reads this to detect a no-op re-send of an existing reschedule."""

    async def test_returns_the_matching_slots_exception_row(self) -> None:
        svc = _service()
        target_date = date(2025, 3, 1)
        target_time = time(6, 0)
        matching_row = {
            "exception_id": uuid4(),
            "original_date": target_date,
            "original_time": target_time,
            "is_cancelled": False,
        }
        sibling_row = {
            "exception_id": uuid4(),
            "original_date": target_date,
            "original_time": time(18, 0),
            "is_cancelled": False,
        }

        async def _read_all(
            sql: str, params: dict, session: object | None = None
        ) -> list[dict]:
            assert params["start_date"] == target_date
            assert params["end_date"] == target_date
            return [sibling_row, matching_row]

        svc._read_all = _read_all  # type: ignore[method-assign]

        result = await svc.exception_on(uuid4(), target_date, target_time)

        assert result == matching_row

    async def test_returns_none_when_no_exception_exists(self) -> None:
        svc = _service()
        svc._read_all = AsyncMock(return_value=[])  # type: ignore[method-assign]

        result = await svc.exception_on(uuid4(), date(2025, 3, 1), time(9, 0))

        assert result is None


# -- cancel -----------------------------------------------------------------


class TestCancelOccurrence:
    async def test_cancel_reverses_attendance_deletes_signups_writes_exception(
        self,
    ) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 1)
        occurrence_time = time(6, 0)
        member_a, member_b = uuid4(), uuid4()
        points_worth = 50
        unended_item = uuid4()

        reverser = AsyncMock()
        reverser.reverse.side_effect = [
            CheckinRemoveResponse(
                removed=True, points_reverted=points_worth
            ),
            CheckinRemoveResponse(
                removed=True,
                points_reverted=points_worth,
                membership_unended=unended_item,
            ),
        ]
        svc = _service(reverser=reverser)
        svc._load_class_in_gym = AsyncMock(  # type: ignore[method-assign]
            return_value={"class_id": class_id, "gym_id": gym_id}
        )
        svc._load_points = AsyncMock(return_value=points_worth)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(  # type: ignore[method-assign]
            return_value=[member_a, member_b]
        )
        svc._delete_signups = AsyncMock(return_value=3)  # type: ignore[method-assign]
        svc._upsert_cancelled_exception = AsyncMock()  # type: ignore[method-assign]

        result = await svc.cancel_occurrence(
            class_id, gym_id, occurrence_date, occurrence_time
        )

        assert reverser.reverse.await_count == 2
        called_members = {
            call.args[1] for call in reverser.reverse.await_args_list
        }
        assert called_members == {member_a, member_b}
        for call in reverser.reverse.await_args_list:
            assert call.args[2:] == (
                gym_id,
                class_id,
                occurrence_date,
                occurrence_time,
                points_worth,
            )

        svc._delete_signups.assert_awaited_once_with(
            ANY, class_id, occurrence_date, occurrence_time
        )
        svc._upsert_cancelled_exception.assert_awaited_once_with(
            ANY, class_id, gym_id, occurrence_date, occurrence_time
        )
        assert result.attendance_rows_deleted == 2
        assert result.signups_deleted == 3
        assert result.memberships_unended == [unended_item]

    async def test_cancel_with_no_attendees_still_deletes_signups(
        self,
    ) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 2)
        occurrence_time = time(18, 0)

        svc = _service()
        svc._load_class_in_gym = AsyncMock(  # type: ignore[method-assign]
            return_value={"class_id": class_id, "gym_id": gym_id}
        )
        svc._load_points = AsyncMock(return_value=50)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc._delete_signups = AsyncMock(return_value=1)  # type: ignore[method-assign]
        svc._upsert_cancelled_exception = AsyncMock()  # type: ignore[method-assign]

        result = await svc.cancel_occurrence(
            class_id, gym_id, occurrence_date, occurrence_time
        )

        assert result.attendance_rows_deleted == 0
        assert result.signups_deleted == 1
        assert result.memberships_unended == []
        svc._upsert_cancelled_exception.assert_awaited_once()

    async def test_cancel_one_slot_never_touches_a_sibling_slots_calls(
        self,
    ) -> None:
        """Cancelling (date, 06:00) issues every DB call scoped to 06:00 —
        the same-day 18:00 sibling's signups/attendance/exception are never
        even queried by this operation (only ITS own slot's calls happen)."""
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 4)
        cancelled_time = time(6, 0)
        sibling_time = time(18, 0)

        svc = _service()
        svc._load_class_in_gym = AsyncMock(  # type: ignore[method-assign]
            return_value={"class_id": class_id, "gym_id": gym_id}
        )
        svc._load_points = AsyncMock(return_value=10)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc._delete_signups = AsyncMock(return_value=0)  # type: ignore[method-assign]
        svc._upsert_cancelled_exception = AsyncMock()  # type: ignore[method-assign]

        await svc.cancel_occurrence(
            class_id, gym_id, occurrence_date, cancelled_time
        )

        # Every scoped call used the cancelled slot's own time...
        assert svc._attendee_members.await_args.args[3] == cancelled_time
        assert svc._delete_signups.await_args.args[3] == cancelled_time
        assert (
            svc._upsert_cancelled_exception.await_args.args[4]
            == cancelled_time
        )
        # ...never the sibling's.
        assert svc._attendee_members.await_args.args[3] != sibling_time
        assert svc._delete_signups.await_args.args[3] != sibling_time


# -- reschedule attendance branch --------------------------------------------


class TestApplyRescheduleAttendance:
    """Direct coverage of the future-wipe / today-past-sync branch."""

    async def test_future_target_wipes_attendance(self) -> None:
        svc = _service()
        svc._reverse_attendance = AsyncMock(return_value=(2, []))  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]
        session = object()
        class_id, gym_id = uuid4(), uuid4()
        original_date = date(2025, 1, 1)
        original_time = time(9, 0)
        new_occurred_at = _occurred_at(_FAR_FUTURE_DATE, time(9, 0))

        await svc.apply_reschedule_attendance(
            session,
            class_id,
            gym_id,
            original_date,
            original_time,
            new_occurred_at,
            True,
        )

        svc._reverse_attendance.assert_awaited_once_with(
            session, class_id, gym_id, original_date, original_time
        )
        svc.sync_attendance_occurred_at.assert_not_awaited()

    async def test_today_or_past_target_syncs_occurred_at(self) -> None:
        svc = _service()
        svc._reverse_attendance = AsyncMock()  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]
        session = object()
        class_id, gym_id = uuid4(), uuid4()
        original_date = date(2025, 1, 1)
        original_time = time(9, 0)
        new_occurred_at = _occurred_at(_FAR_PAST_DATE, time(9, 0))

        await svc.apply_reschedule_attendance(
            session,
            class_id,
            gym_id,
            original_date,
            original_time,
            new_occurred_at,
            False,
        )

        svc.sync_attendance_occurred_at.assert_awaited_once_with(
            session, class_id, original_date, original_time, new_occurred_at
        )
        svc._reverse_attendance.assert_not_awaited()

    async def test_sync_attendance_occurred_at_scoped_to_the_exact_slot(
        self,
    ) -> None:
        """``sync_attendance_occurred_at`` forwards the exact
        ``(original_date, original_time)`` slot untouched to the SQL layer —
        a same-day sibling slot's attendance rows are never in scope."""
        svc = _service()
        session = AsyncMock()
        class_id = uuid4()
        original_date = date(2025, 1, 1)
        original_time = time(6, 0)
        occurred_at = _occurred_at(date(2025, 1, 1), time(6, 30))

        await svc.sync_attendance_occurred_at(
            session, class_id, original_date, original_time, occurred_at
        )

        params = session.execute.await_args.args[1]
        assert params["original_date"] == original_date
        assert params["original_time"] == original_time
        assert params["occurred_at"] == occurred_at


# -- full reschedule_occurrence orchestration --------------------------------


class TestRescheduleOccurrence:
    """End-to-end wiring: version load -> occurrence resolution -> collision
    check -> the future/past attendance branch -> the exception upsert.
    Sign-ups are never touched by this service on a reschedule (they carry
    across the move because the occurrence's identity key is unchanged) —
    there is no sign-up call in ``reschedule_occurrence`` to assert on."""

    def _prep(
        self, svc: ClassesUndoService, class_id: UUID, gym_id: UUID
    ) -> None:
        svc._load_class_in_gym = AsyncMock(  # type: ignore[method-assign]
            return_value={"class_id": class_id, "gym_id": gym_id}
        )
        svc._read_all = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc.assert_no_reschedule_conflict = AsyncMock()  # type: ignore[method-assign]

    async def test_future_target_wipes_and_sign_ups_are_untouched(
        self,
    ) -> None:
        class_id, gym_id = uuid4(), uuid4()
        v1 = _version(class_id=class_id, effective_from=_FAR_PAST)
        original_date = date(2025, 1, 1)
        original_time = time(9, 0)
        exception_id = uuid4()
        row = {
            "exception_id": exception_id,
            "class_id": class_id,
            "original_date": original_date,
            "original_time": original_time,
            "new_date": _FAR_FUTURE_DATE,
        }
        db_pool = _fake_db_pool(row)
        svc = _service(db_pool=db_pool)
        self._prep(svc, class_id, gym_id)
        svc.load_versions = AsyncMock(return_value=[v1])  # type: ignore[method-assign]
        svc._reverse_attendance = AsyncMock(return_value=(1, []))  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]

        resp = await svc.reschedule_occurrence(
            class_id, gym_id, original_date, original_time, _FAR_FUTURE_DATE
        )

        svc._reverse_attendance.assert_awaited_once_with(
            ANY, class_id, gym_id, original_date, original_time
        )
        svc.sync_attendance_occurred_at.assert_not_awaited()
        assert resp.exception_id == exception_id
        assert resp.original_time == original_time
        assert resp.new_date == _FAR_FUTURE_DATE

    async def test_past_target_keeps_and_syncs_occurred_at(self) -> None:
        class_id, gym_id = uuid4(), uuid4()
        v1 = _version(class_id=class_id, effective_from=_FAR_PAST)
        original_date = date(2025, 1, 1)
        original_time = time(9, 0)
        exception_id = uuid4()
        row = {
            "exception_id": exception_id,
            "class_id": class_id,
            "original_date": original_date,
            "original_time": original_time,
            "new_date": _FAR_PAST_DATE,
        }
        db_pool = _fake_db_pool(row)
        svc = _service(db_pool=db_pool)
        self._prep(svc, class_id, gym_id)
        svc.load_versions = AsyncMock(return_value=[v1])  # type: ignore[method-assign]
        svc._reverse_attendance = AsyncMock()  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]

        resp = await svc.reschedule_occurrence(
            class_id, gym_id, original_date, original_time, _FAR_PAST_DATE
        )

        svc._reverse_attendance.assert_not_awaited()
        svc.sync_attendance_occurred_at.assert_awaited_once_with(
            ANY,
            class_id,
            original_date,
            original_time,
            _occurred_at(_FAR_PAST_DATE, original_time),  # v1's slot time
        )
        assert resp.new_date == _FAR_PAST_DATE

    async def test_noop_move_skips_attendance_handling_but_still_upserts(
        self,
    ) -> None:
        """Re-sending the occurrence's CURRENT effective landing (the CRM
        preserves an existing move across an unrelated override save this
        way) is a no-op move: neither the future-wipe nor the today/past
        occurred_at re-sync may run — a wipe would reverse early check-ins
        over a save that changed nothing about the slot — but the exception
        row is still (re)written."""
        class_id, gym_id = uuid4(), uuid4()
        v1 = _version(class_id=class_id, effective_from=_FAR_PAST)
        original_date = date(2025, 1, 1)
        original_time = time(9, 0)
        current_landing = date(2025, 1, 5)  # already the occurrence's target
        exception_id = uuid4()
        row = {
            "exception_id": exception_id,
            "class_id": class_id,
            "original_date": original_date,
            "original_time": original_time,
            "new_date": current_landing,
        }
        db_pool = _fake_db_pool(row)
        svc = _service(db_pool=db_pool)
        self._prep(svc, class_id, gym_id)
        svc.load_versions = AsyncMock(return_value=[v1])  # type: ignore[method-assign]
        # An existing exception already targets `current_landing` -- the
        # request below re-sends that SAME target, changing nothing.
        svc.exception_on = AsyncMock(  # type: ignore[method-assign]
            return_value={
                "new_date": current_landing,
                "new_class_time": None,
                "is_cancelled": False,
            }
        )
        svc._reverse_attendance = AsyncMock()  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]

        resp = await svc.reschedule_occurrence(
            class_id, gym_id, original_date, original_time, current_landing
        )

        svc._reverse_attendance.assert_not_awaited()
        svc.sync_attendance_occurred_at.assert_not_awaited()
        assert resp.exception_id == exception_id
        assert resp.new_date == current_landing
