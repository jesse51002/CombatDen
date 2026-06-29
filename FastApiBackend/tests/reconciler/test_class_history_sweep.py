"""Unit tests for the NON-billing class-history materialize sweep.

No DB / no Stripe: the sweep is driven against a fake db_pool whose successive
``session.execute`` calls return canned class / instance-exception /
range-exception rows, the REAL ``ClassesExpander`` (pure), and a mocked
``ClassesMaterializer``. A fixed ``now`` is patched into the sweep module so the
PAST-occurrence window is deterministic regardless of wall-clock.

Covers: only PAST occurrences (occurred_at < now) are materialized — today's
not-yet-started class is left alone; created-vs-existing counting; cancelled
occurrences are never materialized (expander drops them by default); per-class
error isolation (a bad class counts one error and never aborts the sweep); and
the lookback <= 0 no-op (no query, no write).

The end-to-end materialize-to-DB path is intentionally NOT exercised here: the
``ClassesMaterializer`` DB behavior is covered by the check-in tests, and the
``uq_class_history_occurrence`` migration is not applied to the shared local test
DB, so a live insert would fail at runtime. These tests own the sweep's OWN logic
(windowing, expansion, counting, isolation), which needs no DB.
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.gym_class import RecurringUnit

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.service.classes_expander import ClassesExpander
from src.core.config import settings
from src.reconciler.service.reconciler import (
    reconciler_class_history_sweep as sweep_module,
)
from src.reconciler.service.reconciler.reconciler_class_history_sweep import (
    ClassHistorySweep,
)

_FIXED_NOW = datetime(2026, 6, 15, 12, 0, tzinfo=UTC)
UTC_TZ = "UTC"


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
    timezone: str = UTC_TZ,
    days: tuple[str, ...] = (),
) -> dict:
    """A gym_classes-shaped dict (every expander key) + the gym timezone."""
    row: dict = {
        "class_id": class_id,
        "gym_id": gym_id,
        "class_time": class_time,
        "duration_minutes": duration_minutes,
        "recurring_unit": recurring_unit,
        "recurring_interval": recurring_interval,
        "start_date": start_date,
        "end_date": end_date,
        "timezone": timezone,
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
    """A db_pool whose successive session.execute calls return `results`."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None

    def _execute_result(rows: list[dict]) -> MagicMock:
        res = MagicMock()
        res.mappings.return_value.all.return_value = rows
        return res

    session.execute = AsyncMock(
        side_effect=[_execute_result(rows) for rows in results]
    )
    pool = MagicMock()
    pool.session.return_value = session
    return pool


def _materializer(*, created: list[bool] | bool = True) -> MagicMock:
    """A ClassesMaterializer mock whose find_or_create returns was_created."""
    mat = MagicMock()
    if isinstance(created, bool):
        mat.find_or_create_history = AsyncMock(
            return_value=(uuid4(), created)
        )
    else:
        mat.find_or_create_history = AsyncMock(
            side_effect=[(uuid4(), flag) for flag in created]
        )
    return mat


def _sweep(pool: MagicMock, materializer: MagicMock) -> ClassHistorySweep:
    return ClassHistorySweep(pool, ClassesExpander(), materializer)


# ── only PAST occurrences are materialized ───────────────────────────


async def test_materializes_only_past_occurrences(monkeypatch) -> None:
    monkeypatch.setattr(sweep_module, "datetime", _fixed_datetime())
    monkeypatch.setattr(settings, "class_history_lookback_days", 14)
    class_id, gym_id = uuid4(), uuid4()
    # Daily 18:00 UTC, start 2026-06-01. Window = [2026-06-01 .. 2026-06-15].
    # 06-01..06-14 @18:00 are past; 06-15 @18:00 (>= now 12:00) is the future.
    pool = _pool_with_query_results(
        [[_class_row(class_id=class_id, gym_id=gym_id)], [], []]
    )
    mat = _materializer(created=True)
    result = await _sweep(pool, mat).run()

    assert mat.find_or_create_history.await_count == 14
    assert result.processed == 14
    assert result.changed == 14
    assert result.skipped == 0
    assert result.errors == 0
    # The future (today, not-yet-started) occurrence was never materialized.
    materialized_instants = {
        call.args[2] for call in mat.find_or_create_history.await_args_list
    }
    future = datetime(2026, 6, 15, 18, 0, tzinfo=UTC)
    assert future not in materialized_instants
    assert max(materialized_instants) == datetime(
        2026, 6, 14, 18, 0, tzinfo=UTC
    )


# ── created vs existing counting ─────────────────────────────────────


async def test_counts_created_vs_existing(monkeypatch) -> None:
    monkeypatch.setattr(sweep_module, "datetime", _fixed_datetime())
    monkeypatch.setattr(settings, "class_history_lookback_days", 14)
    class_id, gym_id = uuid4(), uuid4()
    pool = _pool_with_query_results(
        [[_class_row(class_id=class_id, gym_id=gym_id)], [], []]
    )
    # 14 past occurrences: alternate created / already-existing.
    flags = [i % 2 == 0 for i in range(14)]
    mat = _materializer(created=flags)
    result = await _sweep(pool, mat).run()

    assert result.processed == 14
    assert result.changed == sum(flags)
    assert result.skipped == 14 - sum(flags)
    assert result.errors == 0


# ── cancelled occurrences are never materialized ─────────────────────


async def test_cancelled_occurrences_are_not_materialized(monkeypatch) -> None:
    monkeypatch.setattr(sweep_module, "datetime", _fixed_datetime())
    monkeypatch.setattr(settings, "class_history_lookback_days", 14)
    class_id, gym_id = uuid4(), uuid4()
    # A range cancellation covers 06-05..06-08 (4 past days dropped).
    pool = _pool_with_query_results(
        [
            [_class_row(class_id=class_id, gym_id=gym_id)],
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
    mat = _materializer(created=True)
    result = await _sweep(pool, mat).run()

    # 14 past candidates minus the 4 cancelled = 10 materialized.
    assert result.processed == 10
    assert result.changed == 10
    cancelled_days = {
        datetime(2026, 6, d, 18, 0, tzinfo=UTC) for d in (5, 6, 7, 8)
    }
    materialized = {
        call.args[2] for call in mat.find_or_create_history.await_args_list
    }
    assert materialized.isdisjoint(cancelled_days)


# ── per-class error isolation ────────────────────────────────────────


async def test_one_bad_class_does_not_abort_the_sweep(monkeypatch) -> None:
    monkeypatch.setattr(sweep_module, "datetime", _fixed_datetime())
    monkeypatch.setattr(settings, "class_history_lookback_days", 14)
    bad_id, good_id, gym_id = uuid4(), uuid4(), uuid4()
    # The bad class has an unknown IANA timezone -> ZoneInfo raises inside the
    # expander -> the per-class try/except counts ONE error and moves on.
    pool = _pool_with_query_results(
        [
            [
                _class_row(
                    class_id=bad_id, gym_id=gym_id, timezone="Mars/Phobos"
                ),
                _class_row(class_id=good_id, gym_id=gym_id),
            ],
            [],
            [],
        ]
    )
    mat = _materializer(created=True)
    result = await _sweep(pool, mat).run()

    assert result.errors == 1
    # The good class still materialized all 14 of its past occurrences.
    assert result.processed == 14
    assert result.changed == 14
    good_gyms = {
        call.args[0] for call in mat.find_or_create_history.await_args_list
    }
    assert good_gyms == {good_id}


# ── lookback <= 0 is a no-op ─────────────────────────────────────────


async def test_non_positive_lookback_is_a_noop(monkeypatch) -> None:
    monkeypatch.setattr(settings, "class_history_lookback_days", 0)
    pool = _pool_with_query_results([])
    mat = _materializer(created=True)
    result = await _sweep(pool, mat).run()

    assert result.processed == 0
    assert result.changed == 0
    assert result.errors == 0
    # No DB query and no materialize when the sweep is disabled.
    pool.session.assert_not_called()
    mat.find_or_create_history.assert_not_called()


# ── helpers ──────────────────────────────────────────────────────────


def _fixed_datetime() -> type[datetime]:
    """A datetime subclass whose ``now(tz)`` is pinned to ``_FIXED_NOW``."""

    class _FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return _FIXED_NOW

    return _FixedDatetime
