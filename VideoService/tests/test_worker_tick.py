"""WorkerService tick control flow — no DB, no network.

The tick is: acquire the lock → CLEANUP (always) → FINALIZE (always) → the FIRST
heavy step with work, drained fully (scan > enrich > scrape). Covers: lock miss is
a no-op; cleanup + finalize always run; scan is preferred over enrich over scrape;
a step with no work falls through; all-empty is a no-op heavy step; the scrape
drain processes due gyms until none is due; there is NO orphan recovery anymore;
the heartbeat sets the abort flag; and a drain aborts once the flag is set.
"""

from __future__ import annotations

import asyncio

import pytest

from src.worker import worker_config
from src.worker.worker_abort import WorkerAborted
from src.worker.worker_funnel import FunnelResult
from src.worker.worker_scraper import ScrapeResult
from src.worker.worker_service import WorkerService
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


class FakeCleanup:
    def __init__(self) -> None:
        self.calls = 0

    async def run(self) -> int:
        self.calls += 1
        return 0


class FakeFinalizer:
    def __init__(self) -> None:
        self.calls = 0

    async def finalize(self) -> None:
        self.calls += 1


class FakeDrainer:
    """A scan/enrich stand-in: records each drain call + the abort passed, and
    returns a fixed 'did work' bool."""

    def __init__(self, work: bool) -> None:
        self._work = work
        self.calls: list[object] = []

    async def drain(self, abort: object) -> bool:
        self.calls.append(abort)
        return self._work


class FakeSpec:
    async def load(self, gym_id: str) -> SpecData:
        return SpecData(**{**SPEC.__dict__, "gym_id": gym_id})


class FakeScraper:
    def __init__(self) -> None:
        self.scraped: list[SpecData] = []
        self.feed_writes: list[tuple] = []

    async def scrape(self, spec: SpecData) -> ScrapeResult:
        self.scraped.append(spec)
        return ScrapeResult(0.0, 112, 5, 2, 3, 12, 40)

    async def write_feed(self, spec, run_id, candidate_ids):  # noqa: ANN001
        self.feed_writes.append((spec.gym_id, run_id, list(candidate_ids)))
        return len(candidate_ids)


class FakeFunnel:
    async def select(self, spec: SpecData) -> FunnelResult:
        return FunnelResult(candidate_ids=["a", "b"], tier1_count=2, embed_usd=0.01)


class FakeCostLog:
    def __init__(self) -> None:
        self.scrape_logs: list[tuple] = []

    async def log_scrape(  # noqa: ANN001
        self,
        gym_id,
        run_id,
        *,
        youtube_quota_units,
        embed_usd,
        avatar_quota_units=0,
        channels_resolved=0,
    ):
        self.scrape_logs.append(
            (
                gym_id,
                run_id,
                youtube_quota_units,
                embed_usd,
                avatar_quota_units,
                channels_resolved,
            )
        )


def _service(db, lock, *, scan_work=False, enrich_work=False):
    scanner = FakeDrainer(scan_work)
    enricher = FakeDrainer(enrich_work)
    cleanup = FakeCleanup()
    finalizer = FakeFinalizer()
    scraper = FakeScraper()
    parts = {
        "scanner": scanner,
        "enricher": enricher,
        "cleanup": cleanup,
        "finalizer": finalizer,
        "scraper": scraper,
        "funnel": FakeFunnel(),
        "spec": FakeSpec(),
        "cost_log": FakeCostLog(),
    }
    service = WorkerService(
        db_pool=db,
        resource_lock=lock,
        spec=parts["spec"],
        scraper=scraper,
        funnel=parts["funnel"],
        enricher=enricher,
        scanner=scanner,
        cleanup=cleanup,
        finalizer=finalizer,
        cost_log=parts["cost_log"],
    )
    return service, parts


def test_lock_miss_is_noop() -> None:
    db = RoutingFakeDb()
    lock = FakeLock(acquire=False)
    service, parts = _service(db, lock)

    asyncio.run(service.run_tick())

    assert lock.acquired  # tried once
    assert lock.released == []  # never entered the try → never released
    assert parts["cleanup"].calls == 0 and parts["finalizer"].calls == 0
    assert parts["scanner"].calls == [] and parts["enricher"].calls == []


def test_cleanup_and_finalize_always_run_then_release() -> None:
    db = RoutingFakeDb()  # nothing due, no scan/enrich work → all heavy steps empty
    lock = FakeLock()
    service, parts = _service(db, lock)

    asyncio.run(service.run_tick())

    assert parts["cleanup"].calls == 1
    assert parts["finalizer"].calls == 1
    # scan + enrich were both consulted (empty), then scrape found no due gym.
    assert len(parts["scanner"].calls) == 1
    assert len(parts["enricher"].calls) == 1
    assert "select_due_gym" in db.write_names()
    assert "insert_run" not in db.write_names()
    assert len(lock.released) == 1


def test_scan_first_when_scan_has_work() -> None:
    db = RoutingFakeDb()
    lock = FakeLock()
    service, parts = _service(db, lock, scan_work=True)

    asyncio.run(service.run_tick())

    # scan had work → drained + returned; enrich/scrape never consulted.
    assert len(parts["scanner"].calls) == 1
    assert parts["enricher"].calls == []
    assert "select_due_gym" not in db.write_names()
    assert parts["scraper"].scraped == []


def test_enrich_when_scan_empty() -> None:
    db = RoutingFakeDb()
    lock = FakeLock()
    service, parts = _service(db, lock, scan_work=False, enrich_work=True)

    asyncio.run(service.run_tick())

    assert len(parts["scanner"].calls) == 1  # scan checked first (empty)
    assert len(parts["enricher"].calls) == 1  # enrich had work → drained
    assert "select_due_gym" not in db.write_names()  # scrape never reached
    assert parts["scraper"].scraped == []


def test_scrape_when_scan_and_enrich_empty() -> None:
    db = RoutingFakeDb()
    db.ones["insert_run"] = {"run_id": "run-1"}
    # one due gym, then none — the drain processes it and stops.
    db.seq["select_due_gym"] = [{"gym_id": "gym-1"}, None]
    lock = FakeLock()
    service, parts = _service(db, lock)

    asyncio.run(service.run_tick())

    assert len(parts["scanner"].calls) == 1 and len(parts["enricher"].calls) == 1
    # scrape opened a run, scraped, and wrote the funnel candidates as pending.
    assert "insert_run" in db.write_names()
    assert [s.gym_id for s in parts["scraper"].scraped] == ["gym-1"]
    assert parts["scraper"].feed_writes == [("gym-1", "run-1", ["a", "b"])]
    # The logged quota is the run TOTAL (search + the avatar pass), with the
    # avatar share broken out beside it.
    assert parts["cost_log"].scrape_logs == [
        ("gym-1", "run-1", 112, 0.01, 12, 40)
    ]


def test_scrape_drain_processes_multiple_gyms() -> None:
    db = RoutingFakeDb()
    db.ones["insert_run"] = {"run_id": "run-x"}
    db.seq["select_due_gym"] = [{"gym_id": "g1"}, {"gym_id": "g2"}, None]
    lock = FakeLock()
    service, parts = _service(db, lock)

    asyncio.run(service.run_tick())

    # drained BOTH due gyms this tick, then stopped when none remained.
    assert [s.gym_id for s in parts["scraper"].scraped] == ["g1", "g2"]
    assert db.write_names().count("insert_run") == 2


def test_scrape_failure_fails_run_and_logs_incurred_cost() -> None:
    # A transient scrape error AFTER the run is opened must fail the run (so no
    # phantom 'running' run strands the gym) AND still log the already-incurred
    # embed spend — the exception then propagates for the tick loop to log.
    db = RoutingFakeDb()
    db.ones["insert_run"] = {"run_id": "run-1"}
    lock = FakeLock()
    service, parts = _service(db, lock)

    async def boom(spec, run_id, candidate_ids):  # noqa: ANN001
        raise RuntimeError("write_feed boom")

    parts["scraper"].write_feed = boom

    with pytest.raises(RuntimeError):
        asyncio.run(service._scrape_gym("gym-1"))

    assert "fail_run" in db.write_names()  # the run is failed, not left running
    # the funnel embed spend (incurred before write_feed raised) is still recorded,
    # along with the quota the scrape + avatar pass had already spent.
    assert parts["cost_log"].scrape_logs == [
        ("gym-1", "run-1", 112, 0.01, 12, 40)
    ]


def test_scrape_skipped_when_system_cap_reached() -> None:
    db = RoutingFakeDb()
    db.ones["system_count"] = {"runs_in_window": 5}  # == default cap of 5
    db.seq["select_due_gym"] = [{"gym_id": "g1"}, None]
    lock = FakeLock()
    service, parts = _service(db, lock)

    asyncio.run(service.run_tick())

    # the system-cap pre-check short-circuits scrape before any selection.
    assert "select_due_gym" not in db.write_names()
    assert parts["scraper"].scraped == []
    assert len(lock.released) == 1


def test_no_orphan_recovery() -> None:
    # There is no orphan rule: 'running' is a legitimate long-lived state. The
    # tick never fails a run as orphaned — no such SQL is ever routed.
    db = RoutingFakeDb()
    lock = FakeLock()
    service, _ = _service(db, lock)

    asyncio.run(service.run_tick())

    assert "fail_orphans" not in db.execute_names()
    assert "fail_orphans" not in db.write_names()


def test_heartbeat_sets_abort_on_lost_lease(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "worker_heartbeat_seconds", 0)
    db = RoutingFakeDb()
    lock = FakeLock(renew=False)  # the lease is gone
    service, _ = _service(db, lock)
    abort = asyncio.Event()

    asyncio.run(service._heartbeat(token=object(), abort=abort))

    assert abort.is_set()
    assert lock.renews >= 1


def test_scrape_drain_aborts_when_flag_set() -> None:
    db = RoutingFakeDb()
    db.seq["select_due_gym"] = [{"gym_id": "g1"}, None]
    lock = FakeLock()
    service, parts = _service(db, lock)
    abort = asyncio.Event()
    abort.set()  # simulate the heartbeat having lost the lease

    with pytest.raises(WorkerAborted):
        asyncio.run(service._scrape_step(abort))

    assert parts["scraper"].scraped == []  # aborted before selecting a gym
