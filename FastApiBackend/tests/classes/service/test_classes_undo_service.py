"""Unit tests for ``ClassesUndoService`` — cancel + reschedule, re-keyed onto
the versioned schedule model.

``db_pool``/``session`` and the ``CheckinReverser`` are mocked; the recurrence
engines (``ClassesExpander`` + ``ClassesVersionExpander``) are REAL, so
ownership / collision resolution is exercised for real. Individual SQL-hitting
private methods (``_load_class_in_gym``, ``_load_points``,
``_attendee_members``, ``_delete_signups``, ``_upsert_cancelled_exception``,
``_exception_on`` via ``_read_all``) are stubbed per test — the DB boundary —
while the orchestration logic that calls them runs for real.

Coverage:
* the time-aware reschedule collision check (``assert_no_reschedule_conflict``)
  — same instant rejected, same date different time allowed, and a candidate
  reschedule collision resolved against EACH candidate's own owning version
  (not a fixed/current version);
* cancel reverses attendance (via the real ``_reverse_attendance`` loop over
  the mocked reverser), deletes sign-ups, and writes the cancelled exception;
* ``apply_reschedule_attendance``'s branch — a FUTURE target wipes attendance,
  a today/past target re-syncs ``occurred_at`` instead — both directly and via
  the full ``reschedule_occurrence`` orchestration.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time
from unittest.mock import ANY, AsyncMock, MagicMock
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import CheckinRemoveResponse
from src.classes.schema.classes_expander_schema import ExpanderScheduleVersion
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


def _version(
    *,
    effective_from: datetime,
    class_id: UUID | None = None,
    timezone: str = CHICAGO,
    class_time: time = time(9, 0),
    start_date: date = date(2020, 1, 1),
    end_date: date | None = None,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
    new_class_time: time | None = None,
) -> ExpanderScheduleVersion:
    """A daily-recurring schedule version (weekday flags are irrelevant to a
    daily class, so they're omitted)."""
    return ExpanderScheduleVersion(
        schedule_id=uuid4(),
        class_id=class_id or uuid4(),
        gym_id=uuid4(),
        effective_from=effective_from,
        timezone=timezone,
        class_time=class_time,
        duration_minutes=60,
        recurring_unit=recurring_unit,
        recurring_interval=1,
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
        async def _read_all(sql: str, params: dict) -> list[dict]:
            if "original_date <> :original_date" in sql:
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
            "new_date": target,
            "new_class_time": time(14, 0),  # explicit override
        }
        candidate_v2 = {
            "exception_id": uuid4(),
            "original_date": date(2025, 7, 1),  # owned by v2 (after mint)
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


# -- cancel -----------------------------------------------------------------


class TestCancelOccurrence:
    async def test_cancel_reverses_attendance_deletes_signups_writes_exception(
        self,
    ) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 1)
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

        result = await svc.cancel_occurrence(class_id, gym_id, occurrence_date)

        assert reverser.reverse.await_count == 2
        called_members = {
            call.args[1] for call in reverser.reverse.await_args_list
        }
        assert called_members == {member_a, member_b}
        for call in reverser.reverse.await_args_list:
            assert call.args[2:] == (gym_id, class_id, occurrence_date, points_worth)

        svc._delete_signups.assert_awaited_once_with(
            ANY, class_id, occurrence_date
        )
        svc._upsert_cancelled_exception.assert_awaited_once_with(
            ANY, class_id, gym_id, occurrence_date
        )
        assert result.attendance_rows_deleted == 2
        assert result.signups_deleted == 3
        assert result.memberships_unended == [unended_item]

    async def test_cancel_with_no_attendees_still_deletes_signups(
        self,
    ) -> None:
        class_id, gym_id = uuid4(), uuid4()
        occurrence_date = date(2025, 7, 2)

        svc = _service()
        svc._load_class_in_gym = AsyncMock(  # type: ignore[method-assign]
            return_value={"class_id": class_id, "gym_id": gym_id}
        )
        svc._load_points = AsyncMock(return_value=50)  # type: ignore[method-assign]
        svc._attendee_members = AsyncMock(return_value=[])  # type: ignore[method-assign]
        svc._delete_signups = AsyncMock(return_value=1)  # type: ignore[method-assign]
        svc._upsert_cancelled_exception = AsyncMock()  # type: ignore[method-assign]

        result = await svc.cancel_occurrence(class_id, gym_id, occurrence_date)

        assert result.attendance_rows_deleted == 0
        assert result.signups_deleted == 1
        assert result.memberships_unended == []
        svc._upsert_cancelled_exception.assert_awaited_once()


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
        new_occurred_at = _occurred_at(_FAR_FUTURE_DATE, time(9, 0))

        await svc.apply_reschedule_attendance(
            session, class_id, gym_id, original_date, new_occurred_at, True
        )

        svc._reverse_attendance.assert_awaited_once_with(
            session, class_id, gym_id, original_date
        )
        svc.sync_attendance_occurred_at.assert_not_awaited()

    async def test_today_or_past_target_syncs_occurred_at(self) -> None:
        svc = _service()
        svc._reverse_attendance = AsyncMock()  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]
        session = object()
        class_id, gym_id = uuid4(), uuid4()
        original_date = date(2025, 1, 1)
        new_occurred_at = _occurred_at(_FAR_PAST_DATE, time(9, 0))

        await svc.apply_reschedule_attendance(
            session, class_id, gym_id, original_date, new_occurred_at, False
        )

        svc.sync_attendance_occurred_at.assert_awaited_once_with(
            session, class_id, original_date, new_occurred_at
        )
        svc._reverse_attendance.assert_not_awaited()


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
        exception_id = uuid4()
        row = {
            "exception_id": exception_id,
            "class_id": class_id,
            "original_date": original_date,
            "new_date": _FAR_FUTURE_DATE,
        }
        db_pool = _fake_db_pool(row)
        svc = _service(db_pool=db_pool)
        self._prep(svc, class_id, gym_id)
        svc.load_versions = AsyncMock(return_value=[v1])  # type: ignore[method-assign]
        svc._reverse_attendance = AsyncMock(return_value=(1, []))  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]

        resp = await svc.reschedule_occurrence(
            class_id, gym_id, original_date, _FAR_FUTURE_DATE
        )

        svc._reverse_attendance.assert_awaited_once_with(
            ANY, class_id, gym_id, original_date
        )
        svc.sync_attendance_occurred_at.assert_not_awaited()
        assert resp.exception_id == exception_id
        assert resp.new_date == _FAR_FUTURE_DATE

    async def test_past_target_keeps_and_syncs_occurred_at(self) -> None:
        class_id, gym_id = uuid4(), uuid4()
        v1 = _version(class_id=class_id, effective_from=_FAR_PAST)
        original_date = date(2025, 1, 1)
        exception_id = uuid4()
        row = {
            "exception_id": exception_id,
            "class_id": class_id,
            "original_date": original_date,
            "new_date": _FAR_PAST_DATE,
        }
        db_pool = _fake_db_pool(row)
        svc = _service(db_pool=db_pool)
        self._prep(svc, class_id, gym_id)
        svc.load_versions = AsyncMock(return_value=[v1])  # type: ignore[method-assign]
        svc._reverse_attendance = AsyncMock()  # type: ignore[method-assign]
        svc.sync_attendance_occurred_at = AsyncMock()  # type: ignore[method-assign]

        resp = await svc.reschedule_occurrence(
            class_id, gym_id, original_date, _FAR_PAST_DATE
        )

        svc._reverse_attendance.assert_not_awaited()
        svc.sync_attendance_occurred_at.assert_awaited_once_with(
            ANY,
            class_id,
            original_date,
            _occurred_at(_FAR_PAST_DATE, v1.class_time),
        )
        assert resp.new_date == _FAR_PAST_DATE
