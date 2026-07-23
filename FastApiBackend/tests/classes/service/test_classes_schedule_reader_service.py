"""Unit tests for ``ClassesScheduleReaderService.list_effective_instances``
(no DB) — the version-aware schedule board.

There is no materializer and no past/live day-dedup in the versioned model:
the board is pure version expansion (``ClassesVersionExpander``,
``include_cancelled=True``) enriched with instructor names and attendance /
sign-up counts, all keyed by the occurrence's FULL identity ``(class_id,
original_date, original_time)`` — with several slots per day legal, a
date-only key would conflate two same-day occurrences. These tests cover:

* a multi-version class renders its pre-mint days from the OLD version and
  its post-mint days from the NEW version, in the same window;
* a soft-deleted OR PAUSED class renders only occurrences that have already
  ENDED (no in-session/future rows);
* attendance / sign-up counts are keyed by the occurrence's IDENTITY
  ``(class_id, original_date, original_time)`` — a rescheduled occurrence's
  counts follow its ORIGINAL slot, not its displayed ``class_date``;
* every row carries ``original_date`` (distinct from ``class_date`` once
  rescheduled);
* a cancelled occurrence is still emitted, flagged;
* an occurrence rescheduled INTO the window from an ORIGINAL date outside it
  renders here (with its counts keyed by the out-of-window original date),
  via the widened expand bounds;
* an occurrence rescheduled OUT of the window (its original date inside, its
  new_date outside) does not render in the source window — only its
  unaffected sibling days do;
* a class with TWO slots on one date renders TWO independent board rows,
  each with its own ``original_time`` and independently-keyed counts;
* an instance exception bound to ONE slot (e.g. cancelling the 06:00
  occurrence) leaves a same-day SIBLING slot (18:00) completely untouched.

The DB reads (``_read_all``) are stubbed by sql-file name; the real
``ClassesVersionExpander`` (wrapping the real ``ClassesExpander``) does the
actual expansion; ``now`` is pinned via monkeypatching the module's
``datetime`` (mirrors the pattern the deleted materializer test used).
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from dateutil.relativedelta import relativedelta
from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import ALL_DAYS_KEY
from src.classes.service import (
    classes_schedule_reader_service as reader_module,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)

_UTC_TZ = "UTC"


def _class_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    class_name: str = "Test Class",
    max_capacity: int | None = None,
    is_active: bool = True,
    is_deleted: bool = False,
) -> dict:
    """A ``classes_board_classes.sql``-shaped identity row."""
    return {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_name": class_name,
        "class_description": None,
        "max_capacity": max_capacity,
        "allowed_plan_ids": None,
        "image_url": "https://example.test/class.jpg",
        "points_worth": 10,
        "is_active": is_active,
        "is_deleted": is_deleted,
        "created_at": datetime.now(UTC),
    }


def _version_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    effective_from: datetime,
    weekday_slots: dict[str, list[dict]],
    timezone: str = _UTC_TZ,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
    start_date: date = date(2020, 1, 1),
    end_date: date | None = None,
    duration_minutes: int = 60,
) -> dict:
    """A ``classes_schedules_for_gym.sql``-shaped version row."""
    return {
        "schedule_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "effective_from": effective_from,
        "timezone": timezone,
        "duration_minutes": duration_minutes,
        "recurring_unit": recurring_unit,
        "recurring_interval": 1,
        "weekday_slots": weekday_slots,
        "start_date": start_date,
        "end_date": end_date,
    }


def _daily_version_row(
    *, class_id: UUID, gym_id: UUID, effective_from: datetime,
    class_time: time, **kwargs: object,
) -> dict:
    """A single-slot-per-day daily version row."""
    return _version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=effective_from,
        weekday_slots={ALL_DAYS_KEY: [{"time": class_time, "instructor_id": None}]},
        recurring_unit=RecurringUnit.daily,
        **kwargs,
    )


def _instance_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    original_date: date,
    original_time: time = time(9, 0),
    is_cancelled: bool = False,
    new_date: date | None = None,
) -> dict:
    return {
        "exception_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "original_date": original_date,
        "original_time": original_time,
        "is_cancelled": is_cancelled,
        "new_class_time": None,
        "new_duration_minutes": None,
        "new_max_capacity": None,
        "new_instructor_id": None,
        "new_date": new_date,
        "created_at": datetime(2025, 1, 1, tzinfo=UTC),
    }


def _range_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    start_date: date,
    end_date: date,
    is_cancelled: bool = True,
    created_at: datetime = datetime(2025, 1, 1, tzinfo=UTC),
) -> dict:
    return {
        "exception_id": uuid4(),
        "class_id": class_id,
        "gym_id": gym_id,
        "start_date": start_date,
        "end_date": end_date,
        "is_cancelled": is_cancelled,
        "new_instructor_id": None,
        "created_at": created_at,
    }


def _service(
    *,
    classes: list[dict],
    versions: list[dict],
    instances: list[dict] | None = None,
    ranges: list[dict] | None = None,
    attendance: list[dict] | None = None,
    signups: list[dict] | None = None,
) -> ClassesScheduleReaderService:
    sql_map: dict[str, list[dict]] = {
        "classes_board_classes.sql": classes,
        "classes_schedules_for_gym.sql": versions,
        "classes_instance_exceptions_for_window.sql": instances or [],
        "classes_range_exceptions_for_window.sql": ranges or [],
        "classes_gym_instructors.sql": [],
        "classes_attendance_counts.sql": attendance or [],
        "classes_signup_counts.sql": signups or [],
    }

    async def _read_all_stub(sql_file: str, params: dict) -> list[dict]:
        return sql_map.get(sql_file, [])

    service = ClassesScheduleReaderService(
        MagicMock(), ClassesVersionExpander(ClassesExpander())
    )
    service._read_all = AsyncMock(side_effect=_read_all_stub)
    return service


def _fixed_datetime(now: datetime) -> type[datetime]:
    """A datetime subclass whose ``now(tz)`` is pinned to ``now``."""

    class _FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return now

    return _FixedDatetime


async def test_multi_version_class_renders_old_past_new_future(
    monkeypatch,
) -> None:
    """A schedule edit (mint) mid-window: days before the mint render from
    the OLD version's time, days on/after the mint from the NEW version's —
    no materialize, no stored-occurrence side."""
    class_id, gym_id = uuid4(), uuid4()
    mint = datetime(2026, 6, 10, 0, 0, tzinfo=UTC)
    monkeypatch.setattr(
        reader_module, "datetime", _fixed_datetime(mint.replace(hour=12))
    )

    v1 = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    v2 = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=mint,
        class_time=time(18, 0),
    )
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[v1, v2],
    )

    resp = await service.list_effective_instances(
        gym_id, date(2026, 6, 8), date(2026, 6, 12)
    )

    by_date = {row.original_date: row for row in resp.items}
    assert len(by_date) == 5
    assert by_date[date(2026, 6, 8)].resolved_class_time == time(9, 0)
    assert by_date[date(2026, 6, 9)].resolved_class_time == time(9, 0)
    assert by_date[date(2026, 6, 10)].resolved_class_time == time(18, 0)
    assert by_date[date(2026, 6, 11)].resolved_class_time == time(18, 0)
    assert by_date[date(2026, 6, 12)].resolved_class_time == time(18, 0)


async def test_deleted_class_renders_past_only(monkeypatch) -> None:
    """A soft-deleted class's already-ENDED occurrences render; in-session /
    future occurrences do not (the delete wipe already cleared their
    sign-ups/check-ins, so there is nothing to show)."""
    class_id, gym_id = uuid4(), uuid4()
    day1, day2, day3, day4, day5 = (date(2026, 6, i) for i in range(1, 6))
    # 09:00-10:00 daily; "now" is day3 10:00 -> day3 has JUST ended.
    now = datetime(2026, 6, 3, 10, 0, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    service = _service(
        classes=[
            _class_row(class_id=class_id, gym_id=gym_id, is_deleted=True)
        ],
        versions=[version],
    )

    resp = await service.list_effective_instances(gym_id, day1, day5)

    rendered = {row.original_date for row in resp.items}
    assert rendered == {day1, day2, day3}
    assert day4 not in rendered
    assert day5 not in rendered


async def test_paused_class_renders_past_only(monkeypatch) -> None:
    """Same treatment as a soft-deleted class: a PAUSED class
    (``gym_classes.is_active = false``) also renders only occurrences that
    have already ENDED — in-session/future occurrences do not. A paused
    class is un-checkin-able (``CheckinClassResolver``) and un-sign-up-able
    (``SignupService``), so the board must never offer one of its live/future
    occurrences; it stays visible (and un-pausable) only on the
    class-management endpoints (``GET /api/v1/classes``,
    ``GET /api/v1/classes/{class_id}``). See the ``class-system-guide``
    skill."""
    class_id, gym_id = uuid4(), uuid4()
    day1, day2, day3, day4, day5 = (date(2026, 6, i) for i in range(1, 6))
    # 09:00-10:00 daily; "now" is day3 10:00 -> day3 has JUST ended.
    now = datetime(2026, 6, 3, 10, 0, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    service = _service(
        classes=[
            _class_row(class_id=class_id, gym_id=gym_id, is_active=False)
        ],
        versions=[version],
    )

    resp = await service.list_effective_instances(gym_id, day1, day5)

    rendered = {row.original_date for row in resp.items}
    assert rendered == {day1, day2, day3}
    assert day4 not in rendered
    assert day5 not in rendered


async def test_counts_keyed_by_original_date_and_cancelled_included(
    monkeypatch,
) -> None:
    """Attendance/sign-up counts key on the occurrence's identity
    ``(class_id, original_date, original_time)``, not the displayed date —
    a rescheduled occurrence's counts follow it from its original slot. A
    cancelled occurrence is still emitted (flagged), and every row carries
    ``original_date``."""
    class_id, gym_id = uuid4(), uuid4()
    day1, day2, day3 = date(2026, 6, 1), date(2026, 6, 2), date(2026, 6, 3)
    now = datetime(2026, 5, 1, tzinfo=UTC)  # well before the window: nothing
    # has "ended" yet, so the deleted-class filter is moot (class is live).
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    # day2 cancelled; day1 rescheduled onto day3 (effective-date doubling —
    # day3 keeps its own natural occurrence too).
    instances = [
        _instance_row(
            class_id=class_id, gym_id=gym_id, original_date=day2,
            is_cancelled=True,
        ),
        _instance_row(
            class_id=class_id, gym_id=gym_id, original_date=day1,
            new_date=day3,
        ),
    ]
    attendance = [
        {
            "class_id": class_id,
            "original_date": day1,
            "original_time": time(9, 0),
            "attendance_count": 2,
        },
    ]
    signups = [
        {
            "class_id": class_id,
            "original_date": day3,
            "original_time": time(9, 0),
            "signup_count": 1,
        },
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        instances=instances,
        attendance=attendance,
        signups=signups,
    )

    resp = await service.list_effective_instances(gym_id, day1, day3)

    by_original = {row.original_date: row for row in resp.items}
    assert set(by_original) == {day1, day2, day3}

    cancelled = by_original[day2]
    assert cancelled.is_cancelled is True
    assert cancelled.has_instance_exception is True
    assert cancelled.class_date == day2
    assert cancelled.attendance_count == 0
    assert cancelled.signup_count == 0

    moved = by_original[day1]
    assert moved.class_date == day3  # displayed on the new date...
    assert moved.original_date == day1  # ...but keyed by its ORIGINAL date
    assert moved.attendance_count == 2  # follows original_date, not class_date
    assert moved.signup_count == 0
    assert moved.has_instance_exception is True

    natural = by_original[day3]
    assert natural.class_date == day3
    assert natural.original_date == day3
    assert natural.attendance_count == 0
    assert natural.signup_count == 1  # keyed to day3's OWN original_date
    assert natural.is_cancelled is False


async def test_reschedule_into_window_from_outside_original_renders(
    monkeypatch,
) -> None:
    """An occurrence whose ORIGINAL date is BEFORE the view window but whose
    reschedule target (new_date) falls INSIDE it is rendered here — the
    widened expand bounds enumerate it by its original date, then the
    effective-date filter keeps it because its landing IS in-window. Its
    counts are keyed by the out-of-window ORIGINAL date via the same
    widened bounds."""
    class_id, gym_id = uuid4(), uuid4()
    now = datetime(2020, 1, 1, tzinfo=UTC)  # well before anything here
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    window_start, window_end = date(2026, 6, 5), date(2026, 6, 7)
    outside_original = date(2026, 6, 1)  # before window_start
    moved_into_window = date(2026, 6, 6)  # inside the window

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    instances = [
        _instance_row(
            class_id=class_id,
            gym_id=gym_id,
            original_date=outside_original,
            new_date=moved_into_window,
        )
    ]
    attendance = [
        {
            "class_id": class_id,
            "original_date": outside_original,
            "original_time": time(9, 0),
            "attendance_count": 4,
        }
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        instances=instances,
        attendance=attendance,
    )

    resp = await service.list_effective_instances(
        gym_id, window_start, window_end
    )

    by_original = {row.original_date: row for row in resp.items}
    # The moved occurrence renders under its OWN original date...
    assert outside_original in by_original
    moved = by_original[outside_original]
    assert moved.class_date == moved_into_window  # ...displayed on the target
    assert moved.attendance_count == 4  # counted at the ORIGINAL date
    # ...alongside the window's own natural (unaffected) daily occurrences.
    assert by_original.keys() >= {
        outside_original,
        date(2026, 6, 5),
        date(2026, 6, 6),
        date(2026, 6, 7),
    }


async def test_reschedule_out_of_window_does_not_render_in_source_window(
    monkeypatch,
) -> None:
    """An occurrence whose ORIGINAL date is inside the view window but whose
    reschedule target (new_date) falls OUTSIDE it is dropped from this
    window entirely (the effective-date filter excludes it) — only its
    unaffected sibling days render."""
    class_id, gym_id = uuid4(), uuid4()
    now = datetime(2020, 1, 1, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    day1, day2, day3 = date(2026, 6, 1), date(2026, 6, 2), date(2026, 6, 3)
    moved_out_of_window = date(2026, 6, 20)

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    instances = [
        _instance_row(
            class_id=class_id,
            gym_id=gym_id,
            original_date=day2,
            new_date=moved_out_of_window,
        )
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        instances=instances,
    )

    resp = await service.list_effective_instances(gym_id, day1, day3)

    rendered = {row.original_date for row in resp.items}
    assert rendered == {day1, day3}
    assert day2 not in rendered


async def test_cancelling_range_id_distinguishes_range_from_instance_cancel(
    monkeypatch,
) -> None:
    """A range-cancelled day carries the governing range's exception_id on
    the board row; an instance-cancelled day and a plain day both carry
    None — the CRM's only way to tell the two cancel sources apart."""
    class_id, gym_id = uuid4(), uuid4()
    now = datetime(2020, 1, 1, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))

    range_cancelled_day = date(2026, 6, 2)
    instance_cancelled_day = date(2026, 6, 3)
    plain_day = date(2026, 6, 1)

    version = _daily_version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        class_time=time(9, 0),
    )
    ranges = [
        _range_row(
            class_id=class_id,
            gym_id=gym_id,
            start_date=range_cancelled_day,
            end_date=range_cancelled_day,
        )
    ]
    instances = [
        _instance_row(
            class_id=class_id,
            gym_id=gym_id,
            original_date=instance_cancelled_day,
            is_cancelled=True,
        )
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        instances=instances,
        ranges=ranges,
    )

    resp = await service.list_effective_instances(gym_id, plain_day, instance_cancelled_day)

    by_date = {row.original_date: row for row in resp.items}
    assert by_date[range_cancelled_day].is_cancelled is True
    assert by_date[range_cancelled_day].cancelling_range_id == ranges[0]["exception_id"]
    assert by_date[instance_cancelled_day].is_cancelled is True
    assert by_date[instance_cancelled_day].cancelling_range_id is None
    assert by_date[plain_day].is_cancelled is False
    assert by_date[plain_day].cancelling_range_id is None


# -- multi-slot-per-day board rows -----------------------------------------


async def test_two_slot_day_renders_two_independent_board_rows(
    monkeypatch,
) -> None:
    """A class with two slots on the same date renders TWO board rows, each
    carrying its own ``original_time`` and independently-keyed
    attendance/sign-up counts."""
    class_id, gym_id = uuid4(), uuid4()
    now = datetime(2020, 1, 1, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))
    day = date(2026, 6, 1)

    version = _version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        weekday_slots={
            ALL_DAYS_KEY: [
                {"time": time(6, 0), "instructor_id": None},
                {"time": time(18, 0), "instructor_id": None},
            ]
        },
    )
    attendance = [
        {
            "class_id": class_id,
            "original_date": day,
            "original_time": time(6, 0),
            "attendance_count": 3,
        },
    ]
    signups = [
        {
            "class_id": class_id,
            "original_date": day,
            "original_time": time(18, 0),
            "signup_count": 2,
        },
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        attendance=attendance,
        signups=signups,
    )

    resp = await service.list_effective_instances(gym_id, day, day)

    rows = [row for row in resp.items if row.original_date == day]
    assert len(rows) == 2
    by_time = {row.original_time: row for row in rows}
    assert by_time[time(6, 0)].attendance_count == 3
    assert by_time[time(6, 0)].signup_count == 0
    assert by_time[time(18, 0)].signup_count == 2
    assert by_time[time(18, 0)].attendance_count == 0


async def test_instance_exception_on_one_slot_leaves_sibling_untouched(
    monkeypatch,
) -> None:
    """Cancelling the 06:00 occurrence of a 2-slot day leaves the 18:00
    sibling occurrence fully unflagged on the board."""
    class_id, gym_id = uuid4(), uuid4()
    now = datetime(2020, 1, 1, tzinfo=UTC)
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime(now))
    day = date(2026, 6, 1)

    version = _version_row(
        class_id=class_id,
        gym_id=gym_id,
        effective_from=datetime(2020, 1, 1, tzinfo=UTC),
        weekday_slots={
            ALL_DAYS_KEY: [
                {"time": time(6, 0), "instructor_id": None},
                {"time": time(18, 0), "instructor_id": None},
            ]
        },
    )
    instances = [
        _instance_row(
            class_id=class_id,
            gym_id=gym_id,
            original_date=day,
            original_time=time(6, 0),
            is_cancelled=True,
        ),
    ]
    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id)],
        versions=[version],
        instances=instances,
    )

    resp = await service.list_effective_instances(gym_id, day, day)

    rows = {
        row.original_time: row for row in resp.items if row.original_date == day
    }
    assert rows[time(6, 0)].is_cancelled is True
    assert rows[time(6, 0)].has_instance_exception is True
    assert rows[time(18, 0)].is_cancelled is False
    assert rows[time(18, 0)].has_instance_exception is False


# ── window guard (bounded span) ───────────────────────────────────────


def test_validate_window_accepts_a_window_up_to_the_max_span() -> None:
    """A window exactly at the configured max span (default 2 months) is
    allowed — the boundary is inclusive."""
    start = date(2026, 3, 1)
    end = start + relativedelta(months=2)  # exactly the cap
    # Does not raise.
    ClassesScheduleReaderService._validate_window(start, end)


def test_validate_window_rejects_a_window_wider_than_the_max_span() -> None:
    """One day past the max span is a 400-mapped ValueError, not a silent
    million-occurrence expansion."""
    start = date(2026, 3, 1)
    too_wide = start + relativedelta(months=2) + relativedelta(days=1)
    with pytest.raises(ValueError, match="too wide"):
        ClassesScheduleReaderService._validate_window(start, too_wide)


def test_validate_window_rejects_an_inverted_window() -> None:
    """end_date before start_date is a ValueError, not an empty result."""
    with pytest.raises(ValueError, match="on or after"):
        ClassesScheduleReaderService._validate_window(
            date(2026, 3, 10), date(2026, 3, 1)
        )


def test_validate_window_allows_a_single_day() -> None:
    """start == end (a one-day board) is valid."""
    ClassesScheduleReaderService._validate_window(
        date(2026, 3, 1), date(2026, 3, 1)
    )
