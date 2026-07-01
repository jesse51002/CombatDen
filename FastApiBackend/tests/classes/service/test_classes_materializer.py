"""Unit tests for ``ClassesMaterializer.materialize`` / ``materialize_current``
-- the ONE range-parameterized entry point every caller (check-in, the
schedule board, the reconciler sweep) materializes ``class_history`` rows
through.

No real DB: a fake ``db_pool`` returns canned rows for the four sequential
reads ``materialize`` makes (classes, gym timezone, instance exceptions, range
exceptions), the REAL ``ClassesExpander`` does the actual expansion, and
``find_or_create_history`` is patched on the instance (bypassing the DB
entirely) so these tests own only the orchestration: windowing, the forward
cutoff, cancelled-occurrence exclusion, idempotency, and per-class /
per-occurrence error isolation. The find_or_create_history primitive's own
DB behavior is covered by the check-in integration tests.
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.service import classes_materializer as materializer_module
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_materializer import ClassesMaterializer

UTC_TZ = "UTC"
_FIXED_NOW = datetime(2026, 6, 15, 12, 0, tzinfo=UTC)


def _class_row(
    *,
    class_id: UUID,
    gym_id: UUID,
    recurring_unit: RecurringUnit = RecurringUnit.daily,
    recurring_interval: int = 1,
    start_date: date = date(2026, 6, 1),
    end_date: date | None = None,
    class_time: time = time(18, 0),
    duration_minutes: int = 60,
    days: tuple[str, ...] = (),
) -> dict:
    """A gym_classes-shaped dict (every expander key)."""
    row: dict = {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_time": class_time,
        "duration_minutes": duration_minutes,
        "recurring_unit": recurring_unit,
        "recurring_interval": recurring_interval,
        "start_date": start_date,
        "end_date": end_date,
    }
    for day in ("sun", "mon", "tue", "wed", "thu", "fri", "sat"):
        row[day] = day in days
        row[f"{day}_instructor_id"] = None
    return row


def _range_row(
    *,
    class_id: UUID,
    start_date: date,
    end_date: date,
    is_cancelled: bool = False,
) -> dict:
    """A class_range_exceptions-shaped dict (+ class_id for grouping)."""
    return {
        "class_id": class_id,
        "start_date": start_date,
        "end_date": end_date,
        "is_cancelled": is_cancelled,
        "new_instructor_id": None,
        "created_at": datetime(2026, 1, 1, tzinfo=UTC),
    }


def _pool_with_query_results(results: list[list[dict]]) -> MagicMock:
    """A db_pool whose successive session.execute calls return `results`,
    supporting both `.mappings().all()` (classes/instances/ranges) and
    `.mappings().fetchone()` (the gym-timezone read)."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None

    def _execute_result(rows: list[dict]) -> MagicMock:
        res = MagicMock()
        res.mappings.return_value.all.return_value = rows
        res.mappings.return_value.fetchone.return_value = (
            rows[0] if rows else None
        )
        return res

    session.execute = AsyncMock(
        side_effect=[_execute_result(rows) for rows in results]
    )
    pool = MagicMock()
    pool.session.return_value = session
    return pool


def _materializer(
    pool: MagicMock,
    *,
    future_hours: int = 2,
    lookback_days: int = 14,
) -> ClassesMaterializer:
    return ClassesMaterializer(
        pool,
        ClassesExpander(),
        future_hours=future_hours,
        lookback_days=lookback_days,
    )


def _patched_find_or_create(
    mat: ClassesMaterializer,
    *,
    created: list[bool | Exception] | bool = True,
) -> AsyncMock:
    """Patch find_or_create_history on the instance -- bypasses the DB."""
    if isinstance(created, bool):
        mock = AsyncMock(return_value=(uuid4(), created))
    else:
        results = [
            item if isinstance(item, Exception) else (uuid4(), item)
            for item in created
        ]
        mock = AsyncMock(side_effect=results)
    mat.find_or_create_history = mock
    return mock


def _fixed_datetime() -> type[datetime]:
    """A datetime subclass whose ``now(tz)`` is pinned to ``_FIXED_NOW``."""

    class _FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return _FIXED_NOW

    return _FixedDatetime


# ── materialize: creates non-cancelled occurrences in range ──────────────


async def test_materialize_creates_non_cancelled_occurrences_in_range(
    monkeypatch,
) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    # Daily 18:00 UTC, start 2026-06-01. Window = [2026-06-01 .. 2026-06-10].
    pool = _pool_with_query_results(
        [
            [_class_row(class_id=class_id, gym_id=gym_id)],  # classes
            [{"timezone": UTC_TZ}],  # gym timezone
            [],  # instance exceptions
            [],  # range exceptions
        ]
    )
    mat = _materializer(pool)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        gym_id, date(2026, 6, 1), date(2026, 6, 10)
    )

    assert created == 10
    assert mock.await_count == 10
    materialized_instants = {
        call.args[2] for call in mock.await_args_list
    }
    assert materialized_instants == {
        datetime(2026, 6, d, 18, 0, tzinfo=UTC) for d in range(1, 11)
    }


# ── cancelled occurrences are never materialized ──────────────────────────


async def test_cancelled_occurrences_are_not_materialized(monkeypatch) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    pool = _pool_with_query_results(
        [
            [_class_row(class_id=class_id, gym_id=gym_id)],
            [{"timezone": UTC_TZ}],
            [],
            [
                _range_row(
                    class_id=class_id,
                    start_date=date(2026, 6, 5),
                    end_date=date(2026, 6, 8),
                    is_cancelled=True,
                )
            ],
        ]
    )
    mat = _materializer(pool)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        gym_id, date(2026, 6, 1), date(2026, 6, 10)
    )

    # 10 candidates minus the 4 cancelled (06-05..06-08) = 6.
    assert created == 6
    cancelled_days = {
        datetime(2026, 6, d, 18, 0, tzinfo=UTC) for d in (5, 6, 7, 8)
    }
    materialized = {call.args[2] for call in mock.await_args_list}
    assert materialized.isdisjoint(cancelled_days)


# ── idempotent re-run ──────────────────────────────────────────────────────


async def test_second_call_materializes_zero(monkeypatch) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    row = _class_row(class_id=class_id, gym_id=gym_id)
    pool = _pool_with_query_results(
        [
            [row],
            [{"timezone": UTC_TZ}],
            [],
            [],
            # second call's reads:
            [row],
            [{"timezone": UTC_TZ}],
            [],
            [],
        ]
    )
    mat = _materializer(pool)
    mock = _patched_find_or_create(
        mat, created=[True] * 3 + [False] * 3
    )

    first = await mat.materialize(gym_id, date(2026, 6, 1), date(2026, 6, 3))
    second = await mat.materialize(gym_id, date(2026, 6, 1), date(2026, 6, 3))

    assert first == 3
    assert second == 0
    assert mock.await_count == 6


# ── forward cutoff (materialize_future_hours) ─────────────────────────────


async def test_occurrences_beyond_the_future_cutoff_are_not_materialized(
    monkeypatch,
) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    # now = 2026-06-15 12:00 UTC, future_hours=2 -> cutoff 14:00.
    # Daily 13:00 UTC class: 06-15 13:00 is inside the cutoff (past 12:00
    # already started); 06-16 13:00 is far beyond it.
    row = _class_row(
        class_id=class_id,
        gym_id=gym_id,
        class_time=time(13, 0),
        start_date=date(2026, 6, 14),
    )
    pool = _pool_with_query_results(
        [[row], [{"timezone": UTC_TZ}], [], []]
    )
    mat = _materializer(pool, future_hours=2)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        gym_id, date(2026, 6, 14), date(2026, 6, 16)
    )

    assert created == 2  # 06-14 13:00 (past) and 06-15 13:00 (in session)
    materialized = {call.args[2] for call in mock.await_args_list}
    assert datetime(2026, 6, 16, 13, 0, tzinfo=UTC) not in materialized


async def test_future_cutoff_allows_a_not_yet_started_occurrence(
    monkeypatch,
) -> None:
    """A single-day materialize() for an occurrence starting within
    future_hours (e.g. check-in's own call for its open window) DOES
    materialize it -- the cutoff is inclusive of "not yet started"."""
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    # now = 12:00, class at 13:30 -> 1.5h ahead, inside a 2h future_hours.
    row = _class_row(
        class_id=class_id,
        gym_id=gym_id,
        class_time=time(13, 30),
        start_date=date(2026, 6, 15),
    )
    pool = _pool_with_query_results(
        [[row], [{"timezone": UTC_TZ}], [], []]
    )
    mat = _materializer(pool, future_hours=2)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        gym_id, date(2026, 6, 15), date(2026, 6, 15)
    )

    assert created == 1
    assert mock.await_args_list[0].args[2] == datetime(
        2026, 6, 15, 13, 30, tzinfo=UTC
    )


# ── per-class + per-occurrence error isolation ────────────────────────────


async def test_one_bad_class_does_not_abort_materialize(monkeypatch) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    bad_id, good_id, gym_id = uuid4(), uuid4(), uuid4()
    bad_row = _class_row(class_id=bad_id, gym_id=gym_id)
    del bad_row["start_date"]  # malformed row -> to_expander_class raises
    good_row = _class_row(class_id=good_id, gym_id=gym_id)
    pool = _pool_with_query_results(
        [
            [bad_row, good_row],
            [{"timezone": UTC_TZ}],  # one shared, valid gym timezone
            [],
            [],
        ]
    )
    mat = _materializer(pool)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        gym_id, date(2026, 6, 1), date(2026, 6, 3)
    )

    # The bad class's expand fails and is skipped; the good class's 3 daily
    # occurrences still materialize.
    assert created == 3
    good_class_calls = {
        call.args[0] for call in mock.await_args_list
    }
    assert good_class_calls == {good_id}


async def test_one_bad_occurrence_insert_does_not_abort_materialize(
    monkeypatch,
) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    class_id, gym_id = uuid4(), uuid4()
    row = _class_row(class_id=class_id, gym_id=gym_id)
    pool = _pool_with_query_results(
        [[row], [{"timezone": UTC_TZ}], [], []]
    )
    mat = _materializer(pool)
    # 3-day window -> 3 occurrences; the middle insert raises.
    mock = _patched_find_or_create(
        mat, created=[True, RuntimeError("db blip"), True]
    )

    created = await mat.materialize(
        gym_id, date(2026, 6, 1), date(2026, 6, 3)
    )

    assert created == 2
    assert mock.await_count == 3


# ── no classes in the window short-circuits the remaining loads ──────────


async def test_no_classes_in_window_returns_zero_without_further_queries(
    monkeypatch,
) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    pool = _pool_with_query_results([[]])  # only the classes read
    mat = _materializer(pool)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize(
        uuid4(), date(2026, 6, 1), date(2026, 6, 3)
    )

    assert created == 0
    mock.assert_not_called()
    assert pool.session.return_value.execute.await_count == 1


# ── materialize_current: derives [today - lookback, today + future] ──────


async def test_materialize_current_bounds_the_window(monkeypatch) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    pool = _pool_with_query_results([[]])  # classes read returns empty
    mat = _materializer(pool, future_hours=2, lookback_days=14)
    mock = _patched_find_or_create(mat, created=True)
    gym_id = uuid4()

    created = await mat.materialize_current(gym_id)

    assert created == 0
    session = pool.session.return_value
    params = session.execute.await_args_list[0].args[1]
    assert params["gym_id"] == str(gym_id)
    assert params["start_date"] == date(2026, 6, 1)  # 06-15 - 14 days
    assert params["end_date"] == date(2026, 6, 15)  # 12:00 + 2h same day
    mock.assert_not_called()


async def test_materialize_current_non_positive_lookback_is_a_noop(
    monkeypatch,
) -> None:
    monkeypatch.setattr(materializer_module, "datetime", _fixed_datetime())
    pool = _pool_with_query_results([])
    mat = _materializer(pool, lookback_days=0)
    mock = _patched_find_or_create(mat, created=True)

    created = await mat.materialize_current(uuid4())

    assert created == 0
    mock.assert_not_called()
    pool.session.assert_not_called()
