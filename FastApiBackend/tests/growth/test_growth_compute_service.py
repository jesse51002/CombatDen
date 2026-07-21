"""Write-path unit tests for ``GrowthComputeService`` (mocked db_pool, no DB).

The compute path's contract is that nothing a single metric does can take down
the sweep: a missing SQL file, a failing query and an invalid payload must each
cost exactly one metric.

These tests deliberately use REAL registry entries and REAL SQL files (only the
database is mocked), so they also prove the starter files load and template
cleanly through ``load_sql``. ``retention_kpis`` is used as the
not-yet-written metric — its ``.sql`` genuinely does not exist yet.
"""

import json
from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.growth.schema.growth_schema import BreakdownData
from src.growth.service import growth_compute_service as compute_module
from src.growth.service.growth_compute_service import GrowthComputeService
from src.growth.service.growth_registry import (
    GROWTH_REGISTRY,
    GrowthMetricDef,
)

DORMANCY_DAYS = 30
AT_RISK_DAYS = 14
LOCK_KEY = "growth_compute"
LOCK_TTL_SECONDS = 1800


class FakeResourceLock:
    """A ``ResourceLock`` double whose ``try_lock`` yields a fixed answer."""

    def __init__(self, acquired: bool) -> None:
        self._acquired = acquired
        self.keys: list[str] = []
        self.ttls: list[int | None] = []

    @asynccontextmanager
    async def try_lock(self, key: str, ttl_seconds: int | None = None):
        self.keys.append(key)
        self.ttls.append(ttl_seconds)
        yield self._acquired


def make_db_pool(execute_side_effect) -> MagicMock:
    """A db_pool double whose session reads use ``execute_side_effect``."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    session.execute = AsyncMock(side_effect=execute_side_effect)

    db_pool = MagicMock()
    db_pool.session.return_value = session
    db_pool.execute_with_retry = AsyncMock(return_value=None)
    return db_pool


def result_with(rows: list[dict]) -> MagicMock:
    """A SQLAlchemy result double returning ``rows`` from ``.mappings().all()``."""
    result = MagicMock()
    result.mappings.return_value.all.return_value = rows
    return result


def make_service(
    db_pool: MagicMock,
    lock: FakeResourceLock,
) -> GrowthComputeService:
    """The service under test, wired to the doubles."""
    return GrowthComputeService(
        db_pool=db_pool,
        resource_lock=lock,
        dormancy_days=DORMANCY_DAYS,
        at_risk_days=AT_RISK_DAYS,
        lock_key=LOCK_KEY,
        lock_ttl_seconds=LOCK_TTL_SECONDS,
    )


def kpi_payload() -> dict:
    """A minimal valid ``KpiGroupData`` payload."""
    return {
        "tiles": [
            {
                "key": "total",
                "label": "Total Members",
                "value": 7,
                "unit": "count",
            }
        ]
    }


def breakdown_payload() -> dict:
    """A minimal valid ``BreakdownData`` payload."""
    return {
        "unit": "count",
        "items": [{"key": "plan", "label": "Unlimited", "value": 3}],
    }


def one_definition(key: str) -> GrowthMetricDef:
    """The registry entry for ``key``."""
    return next(item for item in GROWTH_REGISTRY if item.key == key)


def upserted_keys(db_pool: MagicMock) -> list[str]:
    """The metric keys the run actually wrote (prune calls excluded)."""
    return [
        call.args[1]["key"]
        for call in db_pool.execute_with_retry.await_args_list
        if "key" in call.args[1]
    ]


@pytest.mark.asyncio
async def test_lock_not_acquired_does_no_work() -> None:
    """Losing the lock race is a clean no-op, not a partial sweep."""
    db_pool = make_db_pool(lambda *args, **kwargs: result_with([]))
    lock = FakeResourceLock(acquired=False)

    await make_service(db_pool, lock).compute_all_gyms()

    assert lock.keys == [LOCK_KEY]
    db_pool.session.return_value.execute.assert_not_awaited()
    db_pool.execute_with_retry.assert_not_awaited()


@pytest.mark.asyncio
async def test_sweep_lease_outlives_the_default_ttl() -> None:
    """The sweep passes its OWN long TTL, never the 60s default.

    A sweep walks every metric for every gym, so the default single-op lease
    would expire mid-run and let a second container start a duplicate sweep.
    """
    db_pool = make_db_pool(lambda *args, **kwargs: result_with([]))
    lock = FakeResourceLock(acquired=True)

    await make_service(db_pool, lock).compute_all_gyms()

    assert lock.ttls == [LOCK_TTL_SECONDS]


@pytest.mark.asyncio
async def test_missing_sql_file_is_skipped(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A registered metric whose .sql has not landed yet is skipped."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("retention_kpis"),),
    )
    db_pool = make_db_pool(lambda *args, **kwargs: result_with([]))

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(uuid4())

    # No query ran and nothing was upserted; only the prune write happened.
    db_pool.session.return_value.execute.assert_not_awaited()
    assert upserted_keys(db_pool) == []
    assert db_pool.execute_with_retry.await_count == 1


@pytest.mark.asyncio
async def test_one_failing_metric_does_not_abort_the_others(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A metric that raises costs exactly that metric."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("members_kpis"), one_definition("members_by_plan")),
    )
    calls = {"n": 0}

    def execute(*args, **kwargs):
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("metric blew up")
        return result_with([{"data": breakdown_payload()}])

    db_pool = make_db_pool(execute)

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(uuid4())

    assert calls["n"] == 2
    assert upserted_keys(db_pool) == ["members_by_plan"]


@pytest.mark.asyncio
async def test_invalid_payload_does_not_abort_the_others(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A payload that fails validation is skipped, never written."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("members_kpis"), one_definition("members_by_plan")),
    )
    payloads = [{"data": {"not": "a kpi group"}}, {"data": breakdown_payload()}]

    def execute(*args, **kwargs):
        return result_with([payloads.pop(0)])

    db_pool = make_db_pool(execute)

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(uuid4())

    assert upserted_keys(db_pool) == ["members_by_plan"]


@pytest.mark.asyncio
async def test_no_returned_row_is_skipped(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A query returning zero rows breaks the one-row contract — skip it."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("members_by_plan"),),
    )
    db_pool = make_db_pool(lambda *args, **kwargs: result_with([]))

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(uuid4())

    assert upserted_keys(db_pool) == []


@pytest.mark.asyncio
async def test_upsert_params_are_well_formed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The UPSERT gets the registry's type and a JSON-serialized payload."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("members_by_plan"),),
    )
    db_pool = make_db_pool(
        lambda *args, **kwargs: result_with([{"data": breakdown_payload()}])
    )
    gym_id = uuid4()

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(gym_id)

    upsert_params = db_pool.execute_with_retry.await_args_list[0].args[1]
    assert upsert_params["gym_id"] == str(gym_id)
    assert upsert_params["key"] == "members_by_plan"
    assert upsert_params["type"] == "breakdown"
    # What is stored is the payload NORMALIZED through the registry's model
    # (defaults filled in), so the serve path validates exactly what was
    # written.
    assert json.loads(upsert_params["data"]) == BreakdownData(
        **breakdown_payload()
    ).model_dump(mode="json")


@pytest.mark.asyncio
async def test_prune_binds_every_registry_key() -> None:
    """The prune keeps exactly the keys the registry still defines.

    Runs against the REAL registry (every metric's query returns nothing here,
    so each is skipped) — the prune must still list the full key set.
    """
    db_pool = make_db_pool(lambda *args, **kwargs: result_with([]))

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(uuid4())

    prune_params = db_pool.execute_with_retry.await_args_list[-1].args[1]
    assert prune_params["keys"] == [
        definition.key for definition in GROWTH_REGISTRY
    ]


@pytest.mark.asyncio
async def test_params_are_restricted_to_the_declared_binds(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Only the binds a query declares are passed — text() raises on extras."""
    monkeypatch.setattr(
        compute_module,
        "GROWTH_REGISTRY",
        (one_definition("members_kpis"), one_definition("at_risk_members")),
    )
    seen: list[dict] = []

    def execute(_statement, params):
        seen.append(params)
        payload = (
            kpi_payload() if len(seen) == 1 else {"columns": [], "rows": []}
        )
        return result_with([{"data": payload}])

    db_pool = make_db_pool(execute)
    gym_id = uuid4()

    await make_service(
        db_pool, FakeResourceLock(acquired=True)
    ).compute_gym(gym_id)

    assert seen[0] == {"gym_id": str(gym_id), "dormancy_days": DORMANCY_DAYS}
    assert seen[1] == {"gym_id": str(gym_id), "at_risk_days": AT_RISK_DAYS}


@pytest.mark.asyncio
async def test_compute_all_gyms_iterates_every_gym(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The sweep runs compute_gym once per gym returned by the id query."""
    monkeypatch.setattr(compute_module, "GROWTH_REGISTRY", ())
    gym_ids = [uuid4(), uuid4()]
    db_pool = make_db_pool(
        lambda *args, **kwargs: result_with(
            [{"gym_id": str(gym_id)} for gym_id in gym_ids]
        )
    )
    service = make_service(db_pool, FakeResourceLock(acquired=True))
    computed: list = []
    monkeypatch.setattr(
        service, "compute_gym", AsyncMock(side_effect=computed.append)
    )

    await service.compute_all_gyms()

    assert computed == gym_ids
