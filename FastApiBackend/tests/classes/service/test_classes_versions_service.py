"""Unit tests for ``ClassesVersionsService`` — the schedule-version mint
engine + the version-change wipe.

``db_pool`` is a bare async-context-manager double; the SQL-hitting private
methods (``_fetchall`` — the shared list-read primitive, keyed by sql-file
name like the schedule reader's ``_read_all`` — and the single-row
``_insert_version`` / ``_load_points`` / ``_delete_signups`` /
``_delete_exception``) are stubbed per test, so the mint/wipe ORCHESTRATION
and the pure survival arithmetic (``_survives_new_version`` /
``_is_future_keyed``, and the real ``ClassesVersionExpander`` they call) run
for real. ``CheckinReverser`` is an ``AsyncMock``.

Coverage:
* deep-equal no-op — including a TIMEZONE-only change, which is a real mint;
* the first version of a class mints with no wipe;
* an exact wall-clock (date + time) match survives a non-time shape change;
* a moved class_time wipes sign-ups, reverses attendance (with the right
  points), and deletes the dangling instance exception;
* a weekday removed from a weekly recurrence wipes that date even when the
  time itself is unchanged;
* a row whose slot already started earlier TODAY is never even collected;
* range exceptions are never read or deleted by this engine;
* ``wipe_all_future`` (the soft-delete path) wipes every future-keyed row
  unconditionally, and no-ops for a never-scheduled class;
* ``remint_timezone`` mints a same-shape, new-timezone version per LIVE class
  and keeps every future-keyed row (the wall-clock match survives since only
  the timezone changed).
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time
from unittest.mock import ANY, AsyncMock, MagicMock
from uuid import uuid4

from src.classes.schema.classes_crud_schema import GymClassScheduleFields
from src.classes.service import classes_versions_service as versions_module
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.classes.service.classes_versions_service import (
    ClassesVersionsService,
)

_DAYS: tuple[str, ...] = ("sun", "mon", "tue", "wed", "thu", "fri", "sat")
_SHAPE_KEYS: tuple[str, ...] = tuple(
    GymClassScheduleFields.model_fields.keys()
)
_DOOMED_DATE = date(2099, 6, 15)  # far future: never "already ran" in a test run


def _shape_row(
    *,
    class_time: time,
    timezone: str = "UTC",
    duration_minutes: int = 60,
    recurring_unit: str = "daily",
    recurring_interval: int = 1,
    start_date: date = date(2020, 1, 1),
    end_date: date | None = None,
    days: tuple[str, ...] = (),
) -> dict:
    """A ``classes_schedules_for_class.sql``-shaped current-version row
    (``recurring_unit`` as the plain string a Postgres enum column returns)."""
    row: dict = {
        "class_time": class_time,
        "duration_minutes": duration_minutes,
        "recurring_unit": recurring_unit,
        "recurring_interval": recurring_interval,
        "start_date": start_date,
        "end_date": end_date,
        "timezone": timezone,
    }
    for day in _DAYS:
        row[day] = day in days
        row[f"{day}_instructor_id"] = None
    return row


def _shape_fields(row: dict) -> GymClassScheduleFields:
    """Build the submitted shape from a ``_shape_row``-style dict."""
    return GymClassScheduleFields(**{key: row[key] for key in _SHAPE_KEYS})


def _other_weekday(exclude: str) -> str:
    """Any weekday short-name other than ``exclude``."""
    return next(day for day in _DAYS if day != exclude)


def _weekday_short(when: date) -> str:
    return _DAYS[(when.weekday() + 1) % 7]


def _fixed_datetime(now: datetime) -> type[datetime]:
    class _FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return now

    return _FixedDatetime


def _fake_db_pool() -> MagicMock:
    pool = MagicMock()
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.commit = AsyncMock()
    pool.session.return_value = session
    return pool


def _service(
    *,
    fetch_map: dict[str, list[dict]] | None = None,
    reverser: AsyncMock | None = None,
) -> ClassesVersionsService:
    fetch_map = fetch_map or {}
    calls: list[tuple[str, dict]] = []

    async def _fetchall(session, sql_file: str, params: dict) -> list[dict]:
        calls.append((sql_file, dict(params)))
        return list(fetch_map.get(sql_file, []))

    svc = ClassesVersionsService(
        db_pool=_fake_db_pool(),
        version_expander=ClassesVersionExpander(ClassesExpander()),
        reverser=reverser or AsyncMock(),
    )
    svc._fetchall = _fetchall  # type: ignore[method-assign]
    svc._fetchall_calls = calls  # type: ignore[attr-defined]
    svc._insert_version = AsyncMock(return_value=uuid4())  # type: ignore[method-assign]
    svc._load_points = AsyncMock(return_value=50)  # type: ignore[method-assign]
    svc._delete_signups = AsyncMock()  # type: ignore[method-assign]
    svc._delete_exception = AsyncMock()  # type: ignore[method-assign]
    return svc


# -- deep-equal no-op ---------------------------------------------------


async def test_no_op_when_shape_and_timezone_both_match() -> None:
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    svc = _service(
        fetch_map={"classes_schedules_for_class.sql": [current_row]}
    )

    result = await svc.mint(
        object(), uuid4(), uuid4(), _shape_fields(current_row), "UTC"
    )

    assert result is None
    svc._insert_version.assert_not_awaited()


async def test_timezone_only_change_is_a_real_mint() -> None:
    """Deep-equal covers shape AND timezone — an identical shape submitted
    with a DIFFERENT timezone is not a no-op."""
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    svc = _service(
        fetch_map={"classes_schedules_for_class.sql": [current_row]}
    )

    result = await svc.mint(
        object(),
        uuid4(),
        uuid4(),
        _shape_fields(current_row),  # identical shape
        "America/Chicago",  # different timezone
    )

    assert result is not None
    svc._insert_version.assert_awaited_once()
    assert svc._insert_version.await_args.args[4] == "America/Chicago"


# -- first version: no wipe ----------------------------------------------


async def test_first_version_mints_with_no_wipe() -> None:
    svc = _service(fetch_map={"classes_schedules_for_class.sql": []})
    new_id = uuid4()
    svc._insert_version = AsyncMock(return_value=new_id)  # type: ignore[method-assign]
    shape = _shape_fields(_shape_row(class_time=time(9, 0)))

    result = await svc.mint(object(), uuid4(), uuid4(), shape, "UTC")

    assert result == new_id
    svc._delete_signups.assert_not_awaited()
    svc._delete_exception.assert_not_awaited()
    svc._reverser.reverse.assert_not_awaited()


# -- exact-slot survival ---------------------------------------------------


async def test_exact_wall_clock_match_survives_a_non_time_shape_change() -> (
    None
):
    class_id, gym_id = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    signup_row = {
        "signup_id": uuid4(),
        "member_id": uuid4(),
        "original_date": _DOOMED_DATE,
        "original_time": time(9, 0),
    }
    attendance_row = {
        "member_id": uuid4(),
        "original_date": _DOOMED_DATE,
        "original_time": time(9, 0),
    }
    exception_row = {"exception_id": uuid4(), "original_date": _DOOMED_DATE}
    svc = _service(
        fetch_map={
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_signups.sql": [signup_row],
            "classes_wipe_collect_attendance.sql": [attendance_row],
            "classes_wipe_collect_exceptions.sql": [exception_row],
        }
    )
    # Only duration changes; the class_time (and every date the recurrence
    # emits) stays the same -> the exact wall-clock slot survives.
    new_shape = _shape_fields(
        _shape_row(class_time=time(9, 0), duration_minutes=90, timezone="UTC")
    )

    result = await svc.mint(object(), class_id, gym_id, new_shape, "UTC")

    assert result is not None
    svc._delete_signups.assert_not_awaited()
    svc._delete_exception.assert_not_awaited()
    svc._reverser.reverse.assert_not_awaited()


# -- moved-time wipe ---------------------------------------------------


async def test_moved_class_time_wipes_signups_attendance_and_exceptions() -> (
    None
):
    class_id, gym_id = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    member_id = uuid4()
    signup_row = {
        "signup_id": uuid4(),
        "member_id": uuid4(),
        "original_date": _DOOMED_DATE,
        "original_time": time(9, 0),
    }
    attendance_row = {
        "member_id": member_id,
        "original_date": _DOOMED_DATE,
        "original_time": time(9, 0),
    }
    exception_row = {"exception_id": uuid4(), "original_date": _DOOMED_DATE}
    svc = _service(
        fetch_map={
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_signups.sql": [signup_row],
            "classes_wipe_collect_attendance.sql": [attendance_row],
            "classes_wipe_collect_exceptions.sql": [exception_row],
        }
    )
    svc._load_points = AsyncMock(return_value=75)  # type: ignore[method-assign]
    new_shape = _shape_fields(_shape_row(class_time=time(19, 0), timezone="UTC"))

    result = await svc.mint(object(), class_id, gym_id, new_shape, "UTC")

    assert result is not None
    svc._delete_signups.assert_awaited_once_with(ANY, class_id, _DOOMED_DATE)
    svc._reverser.reverse.assert_awaited_once_with(
        ANY, member_id, gym_id, class_id, _DOOMED_DATE, 75
    )
    svc._delete_exception.assert_awaited_once_with(ANY, class_id, _DOOMED_DATE)


# -- removed-day wipe ---------------------------------------------------


async def test_weekday_removed_from_recurrence_wipes_even_at_the_same_time() -> (
    None
):
    """The class_time is UNCHANGED (isolating this from the moved-time case)
    — the row is wiped purely because the new weekly recurrence no longer
    fires on that weekday."""
    class_id, gym_id = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    doomed_weekday = _weekday_short(_DOOMED_DATE)
    kept_weekday = _other_weekday(doomed_weekday)
    exception_row = {"exception_id": uuid4(), "original_date": _DOOMED_DATE}
    svc = _service(
        fetch_map={
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_exceptions.sql": [exception_row],
        }
    )
    new_shape = _shape_fields(
        _shape_row(
            class_time=time(9, 0),  # unchanged
            recurring_unit="weekly",
            days=(kept_weekday,),  # excludes the doomed date's weekday
        )
    )

    result = await svc.mint(object(), class_id, gym_id, new_shape, "UTC")

    assert result is not None
    svc._delete_exception.assert_awaited_once_with(ANY, class_id, _DOOMED_DATE)


# -- already-started-today rows are never collected --------------------


async def test_already_started_today_row_is_never_collected(monkeypatch) -> None:
    """A row whose original slot already started earlier TODAY is left
    completely alone — never wiped, regardless of whether the new shape
    would have kept it."""
    fixed_now = datetime(2026, 6, 15, 14, 0, tzinfo=UTC)  # 2pm UTC
    monkeypatch.setattr(versions_module, "datetime", _fixed_datetime(fixed_now))
    class_id, gym_id = uuid4(), uuid4()
    today = date(2026, 6, 15)
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    # This morning's 09:00 class already started before the 2pm mint.
    signup_row = {
        "signup_id": uuid4(),
        "member_id": uuid4(),
        "original_date": today,
        "original_time": time(9, 0),
    }
    svc = _service(
        fetch_map={
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_signups.sql": [signup_row],
        }
    )
    # Moved to 19:00 -- would NOT survive if this row were even considered.
    new_shape = _shape_fields(_shape_row(class_time=time(19, 0), timezone="UTC"))

    result = await svc.mint(object(), class_id, gym_id, new_shape, "UTC")

    assert result is not None
    svc._delete_signups.assert_not_awaited()


# -- range exceptions are never touched ----------------------------------


async def test_range_exceptions_are_never_read_or_deleted() -> None:
    class_id, gym_id = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    svc = _service(
        fetch_map={"classes_schedules_for_class.sql": [current_row]}
    )
    new_shape = _shape_fields(_shape_row(class_time=time(19, 0), timezone="UTC"))

    await svc.mint(object(), class_id, gym_id, new_shape, "UTC")

    sql_files_used = {sql_file for sql_file, _ in svc._fetchall_calls}
    assert not any("range" in sql_file for sql_file in sql_files_used)
    # The engine has no range-exception delete capability at all — range
    # exceptions survive any schedule shape change.
    assert not hasattr(svc, "_delete_range_exception")


# -- wipe_all_future (soft-delete) ---------------------------------------


async def test_wipe_all_future_is_a_noop_without_a_version() -> None:
    svc = _service(fetch_map={"classes_schedules_for_class.sql": []})

    await svc.wipe_all_future(object(), uuid4(), uuid4())

    svc._delete_signups.assert_not_awaited()
    svc._delete_exception.assert_not_awaited()
    svc._reverser.reverse.assert_not_awaited()


async def test_wipe_all_future_wipes_every_future_keyed_row() -> None:
    class_id, gym_id = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    member_id = uuid4()
    svc = _service(
        fetch_map={
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_signups.sql": [
                {
                    "signup_id": uuid4(),
                    "member_id": uuid4(),
                    "original_date": _DOOMED_DATE,
                    "original_time": time(9, 0),
                }
            ],
            "classes_wipe_collect_attendance.sql": [
                {
                    "member_id": member_id,
                    "original_date": _DOOMED_DATE,
                    "original_time": time(9, 0),
                }
            ],
            "classes_wipe_collect_exceptions.sql": [
                {"exception_id": uuid4(), "original_date": _DOOMED_DATE}
            ],
        }
    )
    svc._load_points = AsyncMock(return_value=25)  # type: ignore[method-assign]

    await svc.wipe_all_future(object(), class_id, gym_id)

    # No "new version" survives anything here -- deletion, not a mint.
    svc._delete_signups.assert_awaited_once_with(ANY, class_id, _DOOMED_DATE)
    svc._reverser.reverse.assert_awaited_once_with(
        ANY, member_id, gym_id, class_id, _DOOMED_DATE, 25
    )
    svc._delete_exception.assert_awaited_once_with(ANY, class_id, _DOOMED_DATE)


# -- remint_timezone ------------------------------------------------------


async def test_remint_timezone_mints_per_live_class_and_keeps_rows() -> None:
    gym_id = uuid4()
    live_class, deleted_class = uuid4(), uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="UTC")
    signup_row = {
        "signup_id": uuid4(),
        "member_id": uuid4(),
        "original_date": _DOOMED_DATE,
        "original_time": time(9, 0),
    }
    svc = _service(
        fetch_map={
            "classes_board_classes.sql": [
                {"class_id": live_class, "is_deleted": False},
                {"class_id": deleted_class, "is_deleted": True},
            ],
            "classes_schedules_for_class.sql": [current_row],
            "classes_wipe_collect_signups.sql": [signup_row],
        }
    )
    svc._insert_version = AsyncMock(return_value=uuid4())  # type: ignore[method-assign]

    minted = await svc.remint_timezone(gym_id, "America/Chicago")

    assert minted == 1  # only the live class re-minted
    svc._insert_version.assert_awaited_once()
    assert svc._insert_version.await_args.args[1] == live_class
    assert svc._insert_version.await_args.args[4] == "America/Chicago"
    # Same shape, same wall-clock class_time -> the existing sign-up survives
    # the tz-only remint (nothing wiped).
    svc._delete_signups.assert_not_awaited()


async def test_remint_timezone_skips_a_class_deep_equal_no_op() -> None:
    """A class already on the target timezone (deep-equal, including tz) is
    not counted as minted."""
    gym_id = uuid4()
    live_class = uuid4()
    current_row = _shape_row(class_time=time(9, 0), timezone="America/Chicago")
    svc = _service(
        fetch_map={
            "classes_board_classes.sql": [
                {"class_id": live_class, "is_deleted": False}
            ],
            "classes_schedules_for_class.sql": [current_row],
        }
    )

    minted = await svc.remint_timezone(gym_id, "America/Chicago")

    assert minted == 0
    svc._insert_version.assert_not_awaited()
