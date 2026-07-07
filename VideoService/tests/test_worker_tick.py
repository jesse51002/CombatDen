"""WorkerService tick control flow — no DB, no network.

Covers: lock miss is a no-op; nothing-due returns; the system run cap short-
circuits before selection; orphan recovery marks running runs failed WITHOUT
re-enqueue (there is no queue); a stage exception fails the run; success
completes the run; the heartbeat sets the abort flag on a lost lease; and the
pipeline aborts between stages once the flag is set.
"""

from __future__ import annotations

import asyncio

import pytest

from src.worker import worker_config
from src.worker.worker_cost_log import RunCost
from src.worker.worker_enricher import EnrichCost
from src.worker.worker_funnel import FunnelResult
from src.worker.worker_scanner import ScanResult
from src.worker.worker_scraper import ScrapeResult
from src.worker.worker_service import WorkerAborted, WorkerService
from src.worker.worker_spec import SpecData
from tests.worker_fakes import FakeLock, RoutingFakeDb

SPEC = SpecData(
    gym_id="gym-1",
    disciplines=["mma"],
    videos_desc="v",
    avoid_desc="a",
    queries=["q"],
    criteria_changed=False,
    prev_run_id=None,
)


class RecordingStage:
    """A stage stand-in: records each call, returns a value or raises."""

    def __init__(self, method: str, result: object, raises: Exception | None = None):
        self._method = method
        self._result = result
        self._raises = raises
        self.calls: list[tuple] = []
        setattr(self, method, self._run)

    async def _run(self, *args: object) -> object:
        self.calls.append(args)
        if self._raises is not None:
            raise self._raises
        return self._result


def _service(db, lock, *, scraper=None, funnel=None, enricher=None, scanner=None):
    spec = RecordingStage("load", SPEC)
    scraper = scraper or RecordingStage("scrape", ScrapeResult(0.1, 5, 2, 3))
    funnel = funnel or RecordingStage(
        "select", FunnelResult(candidate_ids=["a"], tier1_count=1, embed_usd=0.0)
    )
    enricher = enricher or RecordingStage("enrich", EnrichCost(llm_usd=0.2))
    scanner = scanner or RecordingStage(
        "scan", ScanResult(llm_usd=0.3, accepted_count=1)
    )
    cost_log = RecordingStage("log", None)
    service = WorkerService(
        db_pool=db,
        resource_lock=lock,
        spec=spec,
        scraper=scraper,
        funnel=funnel,
        enricher=enricher,
        scanner=scanner,
        cost_log=cost_log,
    )
    return service, {
        "spec": spec,
        "scraper": scraper,
        "funnel": funnel,
        "enricher": enricher,
        "scanner": scanner,
        "cost_log": cost_log,
    }


def test_lock_miss_is_noop() -> None:
    db = RoutingFakeDb()
    lock = FakeLock(acquire=False)
    service, stages = _service(db, lock)

    asyncio.run(service.run_tick())

    assert lock.acquired  # tried once
    assert lock.released == []  # never entered the try → never released
    assert db.reads == [] and db.writes == [] and db.executes == []
    assert stages["spec"].calls == []


def test_nothing_due_returns_and_releases() -> None:
    db = RoutingFakeDb()  # system_count → None (→0), select_due_gym → None
    lock = FakeLock()
    service, stages = _service(db, lock)

    asyncio.run(service.run_tick())

    assert "select_due_gym" in db.write_names()  # derivation was consulted
    assert "insert_run" not in db.write_names()  # no run opened
    assert stages["spec"].calls == []
    assert len(lock.released) == 1  # released on the way out


def test_system_cap_reached_skips_selection() -> None:
    db = RoutingFakeDb()
    db.ones["system_count"] = {"runs_in_window": 5}  # == default cap of 5
    lock = FakeLock()
    service, stages = _service(db, lock)

    asyncio.run(service.run_tick())

    # Orphan recovery still runs, but the cap short-circuits BEFORE selection.
    assert "select_due_gym" not in db.write_names()
    assert "insert_run" not in db.write_names()
    assert stages["spec"].calls == []
    assert len(lock.released) == 1


def test_orphan_recovery_marks_failed_without_reenqueue() -> None:
    db = RoutingFakeDb()
    db.session_rows["fail_orphans"] = [{"gym_id": "g-orphan"}]
    lock = FakeLock()
    service, _ = _service(db, lock)

    asyncio.run(service.run_tick())

    names = db.execute_names()
    assert names.count("fail_orphans") == 1
    # There is no queue: an orphan is NOT re-enqueued (the derivation re-selects
    # it when next due). No re-enqueue SQL exists to be routed.
    assert "reenqueue" not in names


def test_success_completes_run_and_runs_all_stages() -> None:
    db = RoutingFakeDb()
    db.ones["select_due_gym"] = {"gym_id": "gym-1"}
    db.ones["insert_run"] = {"run_id": "run-1"}
    lock = FakeLock()
    service, stages = _service(db, lock)

    asyncio.run(service.run_tick())

    assert "complete_run" in db.write_names()
    assert "fail_run" not in db.write_names()
    # every stage ran, in order, and cost was logged with the composed RunCost.
    assert stages["scraper"].calls and stages["funnel"].calls
    assert stages["enricher"].calls and stages["scanner"].calls
    (gym_id, run_id, cost) = stages["cost_log"].calls[0]
    assert (gym_id, run_id) == ("gym-1", "run-1")
    assert isinstance(cost, RunCost) and cost.scan_llm_usd == 0.3
    assert len(lock.released) == 1


def test_stage_exception_fails_run() -> None:
    db = RoutingFakeDb()
    db.ones["select_due_gym"] = {"gym_id": "gym-1"}
    db.ones["insert_run"] = {"run_id": "run-1"}
    lock = FakeLock()
    boom = RecordingStage("scrape", None, raises=RuntimeError("apify down"))
    service, stages = _service(db, lock, scraper=boom)

    asyncio.run(service.run_tick())

    assert "fail_run" in db.write_names()
    assert "complete_run" not in db.write_names()
    # A failed run still advances the last-run watermark, so the derivation will
    # not immediately re-select the gym (no hot-loop). Later stages never ran.
    assert stages["funnel"].calls == [] and stages["scanner"].calls == []
    assert stages["cost_log"].calls == []
    fail_params = [p for n, _, p in db.writes if n == "fail_run"][0]
    assert fail_params["run_id"] == "run-1"
    assert "apify down" in fail_params["error"]


def test_heartbeat_sets_abort_on_lost_lease(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "worker_heartbeat_seconds", 0)
    db = RoutingFakeDb()
    lock = FakeLock(renew=False)  # the lease is gone
    service, _ = _service(db, lock)
    abort = asyncio.Event()

    # _heartbeat returns as soon as a renew fails (after setting the flag).
    asyncio.run(service._heartbeat(token=object(), abort=abort))

    assert abort.is_set()
    assert lock.renews >= 1


def test_pipeline_aborts_between_stages() -> None:
    db = RoutingFakeDb()
    lock = FakeLock()
    abort = asyncio.Event()

    class AbortingScraper:
        def __init__(self) -> None:
            self.calls: list[tuple] = []

        async def scrape(self, spec):  # noqa: ANN001
            self.calls.append((spec,))
            abort.set()  # simulate the heartbeat losing the lock mid-stage
            return ScrapeResult(0.0, 0, 0, 0)

    scraper = AbortingScraper()
    funnel = RecordingStage("select", FunnelResult())
    service, _ = _service(db, lock, scraper=scraper, funnel=funnel)

    with pytest.raises(WorkerAborted):
        asyncio.run(service._run_pipeline("gym-1", "run-1", abort))

    assert scraper.calls  # scrape ran
    assert funnel.calls == []  # the abort check after scrape stopped the pipeline
