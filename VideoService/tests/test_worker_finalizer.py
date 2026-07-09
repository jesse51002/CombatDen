"""WorkerFinalizer — no DB (routed fake).

Runs two passes each tick, IN ORDER: complete (a run whose terminal fraction
reaches ``worker_run_complete_fraction``) then fail (0-row-after-grace, else
TTL-exceeded). A fakes-only suite can't execute the real SQL, so it asserts the
passes run in the right order with the right thresholds, and that the SQL encodes
the completion / 0-row / TTL rules. rowcount drives the (logged) counts."""

from __future__ import annotations

import asyncio

from src.worker.worker_config import settings
from src.worker.worker_finalizer import WorkerFinalizer
from tests.worker_fakes import RoutingFakeDb


def _executed(db: RoutingFakeDb, name: str):
    return [(s, p) for n, s, p in db.executes if n == name]


def test_completes_before_fails_with_thresholds() -> None:
    db = RoutingFakeDb()
    # simulate 2 runs completed, 1 failed (rowcount = len(session_rows)).
    db.session_rows["finalize_complete"] = [{"run_id": "r1"}, {"run_id": "r2"}]
    db.session_rows["finalize_fail"] = [{"run_id": "r3"}]

    asyncio.run(WorkerFinalizer(db).finalize())

    # completion pass runs BEFORE the fail pass (a >=90% run past TTL completes).
    assert db.execute_names() == ["finalize_complete", "finalize_fail"]

    complete_sql, complete_params = _executed(db, "finalize_complete")[0]
    assert complete_params == {
        "complete_fraction": settings.worker_run_complete_fraction
    }
    # the completion rule: terminal (accepted/rejected) fraction of ALL rows.
    assert "scan_status IN ('accepted', 'rejected')" in complete_sql
    assert ">= :complete_fraction" in complete_sql

    fail_sql, fail_params = _executed(db, "finalize_fail")[0]
    assert fail_params == {
        "zero_row_grace_hours": settings.worker_zero_row_grace_hours,
        "run_ttl_hours": settings.worker_run_ttl_hours,
    }
    # the fail rules: 0-row after grace, else TTL exceeded.
    assert "'no feed rows'" in fail_sql
    assert "'run ttl exceeded'" in fail_sql
    assert ":zero_row_grace_hours" in fail_sql
    assert ":run_ttl_hours" in fail_sql


def test_finalize_runs_both_passes_when_idle() -> None:
    db = RoutingFakeDb()  # no rows → both passes affect 0 runs, still run

    asyncio.run(WorkerFinalizer(db).finalize())

    assert db.execute_names() == ["finalize_complete", "finalize_fail"]
