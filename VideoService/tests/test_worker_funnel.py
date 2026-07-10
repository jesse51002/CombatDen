"""WorkerFunnel candidate selection — no DB, no network.

Covers: tier 1 is always included and ordered ahead of tier 2; the budget caps
the union (tier 1 first, truncated by relevance if it alone exceeds the budget,
then tier 2); and incremental mode excludes the previous run's verdicted ids.
"""

from __future__ import annotations

import asyncio

from src.worker import worker_config, worker_funnel
from src.worker.worker_funnel import WorkerFunnel
from src.worker.worker_spec import SpecData
from tests.worker_fakes import FakeLLM, RoutingFakeDb


def _spec(*, criteria_changed=True, prev_run_id=None) -> SpecData:
    return SpecData(
        gym_id="gym-1",
        disciplines=["mma"],
        videos_desc="v",
        avoid_desc="a",
        queries=["q1", "q2"],
        criteria_changed=criteria_changed,
        prev_run_id=prev_run_id,
    )


def test_tier1_first_then_tier2() -> None:
    db = RoutingFakeDb()
    db.rows["tier1"] = [
        {"video_id": "a", "relevance_index": 0},
        {"video_id": "b", "relevance_index": 1},
    ]
    db.rows["tier2"] = [{"video_id": "c", "distance": 0.05}]  # per probe
    llm = FakeLLM(embed_cost=0.01)
    funnel = WorkerFunnel(db, llm)

    result = asyncio.run(funnel.select(_spec()))

    assert result.candidate_ids == ["a", "b", "c"]  # tier1 order, then tier2
    assert result.tier1_count == 2 and result.tier2_count == 1
    assert result.embed_usd == 0.01
    assert len(llm.embed_calls) == 1  # ALL queries embedded in one call
    assert llm.embed_calls[0]["texts"] == ["q1", "q2"]


def test_budget_caps_tier1_and_skips_probes(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "scan_budget_per_run", 2)
    db = RoutingFakeDb()
    # The SQL applies ORDER BY relevance + LIMIT :budget in-DB, so the fake returns
    # the already-capped set (2 rows). When tier-1 fills the budget, probes are
    # skipped and no embed spend is paid.
    db.rows["tier1"] = [
        {"video_id": "a", "relevance_index": 0},
        {"video_id": "b", "relevance_index": 1},
    ]
    db.rows["tier2"] = [{"video_id": "z", "distance": 0.01}]
    llm = FakeLLM()
    funnel = WorkerFunnel(db, llm)

    result = asyncio.run(funnel.select(_spec()))

    assert result.candidate_ids == ["a", "b"]
    assert result.tier2_count == 0
    assert llm.embed_calls == []  # tier-1 filled the budget → no probes
    assert db.read_params("tier1")[0]["budget"] == 2  # budget pushed into SQL


def test_budget_fills_remaining_with_tier2(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "scan_budget_per_run", 3)
    db = RoutingFakeDb()
    db.rows["tier1"] = [
        {"video_id": "a", "relevance_index": 0},
        {"video_id": "b", "relevance_index": 1},
    ]
    db.rows["tier2"] = [
        {"video_id": "c", "distance": 0.05},
        {"video_id": "d", "distance": 0.09},
    ]
    funnel = WorkerFunnel(db, FakeLLM())

    result = asyncio.run(funnel.select(_spec()))

    # 2 tier-1 + 1 tier-2 (best distance) = budget of 3.
    assert result.candidate_ids == ["a", "b", "c"]


def test_incremental_excludes_prior_verdicted() -> None:
    db = RoutingFakeDb()
    # The prior run's verdicted ids are excluded IN-DB (the :exclude_ids bind), so
    # the fake returns the already-filtered tier-1 set ('a' gone); the test asserts
    # the exclude bind carries the prior run's verdicts.
    db.rows["tier1"] = [{"video_id": "b", "relevance_index": 1}]
    db.rows["prev_verdicts"] = [{"video_id": "a"}]  # a was scanned last run
    db.rows["tier2"] = []
    funnel = WorkerFunnel(db, FakeLLM())

    result = asyncio.run(
        funnel.select(_spec(criteria_changed=False, prev_run_id="prev-1"))
    )

    assert result.candidate_ids == ["b"]  # 'a' carried forward, not rescanned
    # the exclude set is read from the previous run's verdicts...
    assert db.read_params("prev_verdicts")[0] == {"prev_run_id": "prev-1"}
    # ...and threaded into tier-1 as the :exclude_ids bind.
    assert db.read_params("tier1")[0]["exclude_ids"] == ["a"]


def test_tier1_sql_pushes_budget_and_exclude() -> None:
    # The budget + incremental exclusion are pushed INTO the SQL (LIMIT + an
    # anti-condition) rather than loading the whole query-overlap pool into Python
    # to slice/filter.
    sql = (worker_funnel.SQL_DIR / "worker_funnel_tier1.sql").read_text(
        encoding="utf-8"
    )
    assert "LIMIT :budget" in sql
    assert "NOT (video_id = ANY(:exclude_ids))" in sql


def test_fresh_run_does_not_read_prior_verdicts() -> None:
    db = RoutingFakeDb()
    db.rows["tier1"] = [{"video_id": "a", "relevance_index": 0}]
    funnel = WorkerFunnel(db, FakeLLM())

    asyncio.run(funnel.select(_spec(criteria_changed=True, prev_run_id="prev-1")))

    assert db.read_params("prev_verdicts") == []  # not consulted on a fresh run
