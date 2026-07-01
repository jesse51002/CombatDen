"""Unit tests for ``ClassesScheduleReaderService.list_effective_instances``
(no DB) — specifically the past/live dedup by ``(class_id, gym-local day)``.

``_board_rows_for_class`` builds the live (in-session/upcoming) rows from the
current, editable ``gym_classes`` definition while ``past_by_class`` builds
the immutable, already-ended rows from ``class_history``. ``PUT
/classes/{id}`` edits ``gym_classes`` without syncing existing
``class_history`` rows, so after a default-TIME edit a day can carry BOTH a
materialized past row (old time, ended) AND a live-expander row (new time,
not-yet-ended) — the same class rendering twice for that day. These tests
reproduce that duplicate and confirm the dedup keeps exactly one row, while a
normal (unedited) day still resolves to exactly one row either way.

The DB reads (``_read_all`` / ``_gym_timezone``) are stubbed by sql-file name;
the real ``ClassesExpander`` does the actual expansion; ``now`` is pinned via
monkeypatching the module's ``datetime`` (mirrors
``test_classes_materializer.py``'s ``_fixed_datetime`` pattern).
"""

from datetime import UTC, date, datetime, time, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.service import (
    classes_schedule_reader_service as reader_module,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)

_DAY = date(2026, 6, 15)
_FIXED_NOW = datetime(2026, 6, 15, 12, 0, tzinfo=UTC)


def _class_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    class_time: time,
) -> dict:
    """A classes_load_for_window.sql-shaped row: daily-recurring, covering
    ``_DAY``, at the CURRENT (possibly edited) default time."""
    row = {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_name": "Test Class",
        "class_time": class_time,
        "duration_minutes": 60,
        "recurring_unit": RecurringUnit.daily,
        "recurring_interval": 1,
        "start_date": _DAY - timedelta(days=30),
        "end_date": None,
        "max_capacity": None,
        "image_url": None,
        "points_worth": 10,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = True
        row[f"{day}_instructor_id"] = None
    return row


def _past_row(*, class_id: UUID, gym_id: UUID, occurred_at: datetime) -> dict:
    """A classes_board_past_history.sql-shaped row: an already-materialized,
    ended occurrence."""
    return {
        "class_id": class_id,
        "gym_id": gym_id,
        "instructor_id": None,
        "occurred_at": occurred_at,
        "duration_minutes": 60,
        "class_name": "Test Class",
        "image_url": None,
        "points_worth": 10,
        "max_capacity": None,
        "attendance_count": 0,
    }


def _service(
    *,
    classes: list[dict],
    past_rows: list[dict],
) -> ClassesScheduleReaderService:
    sql_map: dict[str, list[dict]] = {
        "classes_load_for_window.sql": classes,
        "classes_instance_exceptions_for_window.sql": [],
        "classes_range_exceptions_for_window.sql": [],
        "classes_gym_instructors.sql": [],
        "classes_attendance_counts.sql": [],
        "classes_signup_counts.sql": [],
        "classes_board_past_history.sql": past_rows,
    }

    async def _read_all_stub(sql_file: str, params: dict) -> list[dict]:
        return sql_map.get(sql_file, [])

    service = ClassesScheduleReaderService(MagicMock(), ClassesExpander(), MagicMock())
    service._gym_timezone = AsyncMock(return_value="UTC")
    service._read_all = AsyncMock(side_effect=_read_all_stub)
    service._materializer = MagicMock()
    service._materializer.materialize = AsyncMock(return_value=0)
    return service


def _fixed_datetime() -> type[datetime]:
    """A datetime subclass whose ``now(tz)`` is pinned to ``_FIXED_NOW``."""

    class _FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return _FIXED_NOW

    return _FixedDatetime


async def test_default_time_edit_after_materialize_does_not_duplicate(
    monkeypatch,
) -> None:
    """The bug: the class's default time was edited (9am -> 6pm) for a day
    already materialized under the OLD time. Before the fix, this rendered
    TWO rows for the day (the past 9am row + a live 6pm row, since 6pm hasn't
    ended yet at noon). After the fix, the materialized past row wins and the
    live row for that same day is dropped -- exactly one row."""
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()

    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id, class_time=time(18, 0))],
        past_rows=[
            _past_row(
                class_id=class_id,
                gym_id=gym_id,
                occurred_at=datetime(2026, 6, 15, 9, 0, tzinfo=UTC),
            )
        ],
    )

    resp = await service.list_effective_instances(gym_id, _DAY, _DAY)

    assert len(resp.items) == 1
    row = resp.items[0]
    # The materialized (old-time) row is the one that survives -- authoritative
    # for a day that already ran.
    assert row.resolved_class_time == time(9, 0)
    assert row.occurred_at == datetime(2026, 6, 15, 9, 0, tzinfo=UTC)


async def test_upcoming_unedited_day_renders_once(monkeypatch) -> None:
    """A normal day that hasn't run yet (no class_history row) -> exactly one
    row, from the live expansion -- unaffected by the dedup."""
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()

    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id, class_time=time(18, 0))],
        past_rows=[],
    )

    resp = await service.list_effective_instances(gym_id, _DAY, _DAY)

    assert len(resp.items) == 1
    assert resp.items[0].resolved_class_time == time(18, 0)
    assert resp.items[0].is_cancelled is False


async def test_ended_unedited_day_renders_once_from_history(monkeypatch) -> None:
    """A normal day that already ran, definition unchanged (live and history
    agree on the time) -> exactly one row, from class_history -- the live
    row is already excluded by the ended-filter regardless of the dedup."""
    monkeypatch.setattr(reader_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()

    service = _service(
        classes=[_class_row(class_id=class_id, gym_id=gym_id, class_time=time(9, 0))],
        past_rows=[
            _past_row(
                class_id=class_id,
                gym_id=gym_id,
                occurred_at=datetime(2026, 6, 15, 9, 0, tzinfo=UTC),
            )
        ],
    )

    resp = await service.list_effective_instances(gym_id, _DAY, _DAY)

    assert len(resp.items) == 1
    assert resp.items[0].resolved_class_time == time(9, 0)
