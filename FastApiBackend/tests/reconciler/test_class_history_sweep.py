"""Unit tests for the NON-billing class-history materialize reconciler step.

``ClassHistorySweep`` is now a THIN per-gym loop: list every gym, call the
shared ``ClassesMaterializer.materialize_current`` for each, and aggregate the
result with per-gym error isolation. The load + expand + per-occurrence write
+ windowing logic itself lives in ``ClassesMaterializer`` (covered by
``tests/classes/service/test_classes_materializer.py``), so these tests drive
the sweep against a fake db_pool (for the gym list) and a mocked
``ClassesMaterializer`` (for ``materialize_current``), covering only the
sweep's OWN logic: gym listing, per-gym counting, and per-gym error isolation.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from src.reconciler.service.reconciler.reconciler_class_history_sweep import (
    ClassHistorySweep,
)


def _pool_with_gym_ids(gym_ids: list[UUID]) -> MagicMock:
    """A db_pool whose one session.execute call returns gym id rows."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None

    res = MagicMock()
    res.mappings.return_value.all.return_value = [
        {"gym_id": gym_id} for gym_id in gym_ids
    ]
    session.execute = AsyncMock(return_value=res)

    pool = MagicMock()
    pool.session.return_value = session
    return pool


def _materializer(*, created: list[int] | int | Exception) -> MagicMock:
    """A ClassesMaterializer mock whose materialize_current is scripted."""
    mat = MagicMock()
    if isinstance(created, Exception):
        mat.materialize_current = AsyncMock(side_effect=created)
    elif isinstance(created, int):
        mat.materialize_current = AsyncMock(return_value=created)
    else:
        mat.materialize_current = AsyncMock(side_effect=created)
    return mat


def _sweep(pool: MagicMock, materializer: MagicMock) -> ClassHistorySweep:
    return ClassHistorySweep(pool, materializer)


# ── happy path: one materialize_current call per gym, aggregated ─────────


async def test_calls_materialize_current_once_per_gym() -> None:
    gym_a, gym_b, gym_c = uuid4(), uuid4(), uuid4()
    pool = _pool_with_gym_ids([gym_a, gym_b, gym_c])
    mat = _materializer(created=[5, 0, 2])

    result = await _sweep(pool, mat).run()

    assert mat.materialize_current.await_count == 3
    called_gyms = {
        call.args[0] for call in mat.materialize_current.await_args_list
    }
    assert called_gyms == {gym_a, gym_b, gym_c}
    assert result.processed == 3
    assert result.changed == 7  # 5 + 0 + 2
    assert result.errors == 0


async def test_no_gyms_is_a_noop() -> None:
    pool = _pool_with_gym_ids([])
    mat = _materializer(created=0)

    result = await _sweep(pool, mat).run()

    assert result.processed == 0
    assert result.changed == 0
    assert result.errors == 0
    mat.materialize_current.assert_not_called()


# ── per-gym error isolation ───────────────────────────────────────────────


async def test_one_bad_gym_does_not_abort_the_sweep() -> None:
    bad_gym, good_gym = uuid4(), uuid4()
    pool = _pool_with_gym_ids([bad_gym, good_gym])
    # The bad gym's materialize_current raises; the good gym still runs.
    mat = _materializer(created=[RuntimeError("boom"), 4])

    result = await _sweep(pool, mat).run()

    assert result.processed == 2
    assert result.changed == 4
    assert result.errors == 1
