"""WorkerScanner batched scan + carry-forward feed write — no DB, no network.

Covers: batch splitting; a batch id that gets no verdict is retried once then
defaulted to rejected; ids the model returns that were not in the batch are
dropped; and the carry-forward clause selection (fresh → manual-only, incremental
→ all, no prev run → no carry-forward).
"""

from __future__ import annotations

import asyncio
import re

from src.worker import worker_config
from src.worker.schema.scan_batch import ScanBatchResult, ScanVerdictItem
from src.worker.worker_scanner import WorkerScanner
from src.worker.worker_spec import SpecData
from tests.worker_fakes import FakeLLM, RoutingFakeDb


def _spec(*, criteria_changed=True, prev_run_id=None) -> SpecData:
    return SpecData(
        gym_id="gym-1",
        disciplines=["mma"],
        videos_desc="worth surfacing",
        avoid_desc="avoid",
        queries=["q"],
        criteria_changed=criteria_changed,
        prev_run_id=prev_run_id,
    )


def _candidate(vid: str) -> dict:
    return {
        "video_id": vid,
        "title": f"Title {vid}",
        "channel_name": "Chan",
        "genre": "educational",
        "summary": "summary text",
    }


def _handler(good: set[str], *, omit: set[str] = frozenset(),
             hallucinate: bool = False, cost: float = 0.05):
    def handler(call: dict) -> tuple[ScanBatchResult, float]:
        prompt = call["messages"][0]["content"]
        ids = re.findall(r"video_id: (\S+)", prompt)
        verdicts = [
            ScanVerdictItem(video_id=i, is_good=(i in good))
            for i in ids
            if i not in omit
        ]
        if hallucinate:
            verdicts.append(ScanVerdictItem(video_id="ZZZ", is_good=True))
        return ScanBatchResult(verdicts=verdicts), cost

    return handler


def _verdict_rows(db: RoutingFakeDb) -> list[dict]:
    lists = [p for n, _, p in db.executes if n == "insert_verdict"]
    return lists[0] if lists else []


def _sql_body(sql: str) -> str:
    """The SQL with -- comment lines stripped (the comment explains both modes,
    so the assertions must look only at the executable clause)."""
    return "\n".join(
        line for line in sql.splitlines() if not line.strip().startswith("--")
    )


def test_batch_splitting(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "scan_batch_size", 2)
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = [_candidate("a"), _candidate("b"), _candidate("c")]
    llm = FakeLLM(structured=_handler({"a", "b", "c"}))
    scanner = WorkerScanner(db, llm)

    result = asyncio.run(scanner.scan(_spec(), "run-1", ["a", "b", "c"]))

    assert len(llm.structured_calls) == 2  # 3 candidates in batches of 2
    assert result.accepted_count == 3 and result.rejected_count == 0
    assert {r["video_id"] for r in _verdict_rows(db)} == {"a", "b", "c"}


def test_missing_id_retried_then_rejected() -> None:
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = [_candidate("a"), _candidate("b")]
    # 'b' never gets a verdict — even on the retry pass.
    llm = FakeLLM(structured=_handler({"a"}, omit={"b"}))
    scanner = WorkerScanner(db, llm)

    result = asyncio.run(scanner.scan(_spec(), "run-1", ["a", "b"]))

    assert len(llm.structured_calls) == 2  # first pass + one retry of the miss
    assert result.accepted_count == 1 and result.rejected_count == 1
    rows = {r["video_id"]: r for r in _verdict_rows(db)}
    assert rows["a"]["scan_status"] == "accepted" and rows["a"]["rejected_at"] is None
    assert rows["b"]["scan_status"] == "rejected"
    assert rows["b"]["rejected_at"] is not None  # rejected rows stamp the time


def test_hallucinated_ids_dropped() -> None:
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = [_candidate("a")]
    llm = FakeLLM(structured=_handler({"a"}, hallucinate=True))
    scanner = WorkerScanner(db, llm)

    result = asyncio.run(scanner.scan(_spec(), "run-1", ["a"]))

    assert {r["video_id"] for r in _verdict_rows(db)} == {"a"}  # ZZZ dropped
    assert result.accepted_count == 1


def test_carry_forward_fresh_copies_only_manual() -> None:
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = []  # no candidates — isolate the carry-forward
    scanner = WorkerScanner(db, FakeLLM())

    asyncio.run(
        scanner.scan(_spec(criteria_changed=True, prev_run_id="prev-1"), "run-1", [])
    )

    cf_sql = _sql_body([s for n, s, _ in db.executes if n == "carry_forward"][0])
    assert "curation_type = 'manual'" in cf_sql  # fresh → only owner verdicts


def test_carry_forward_incremental_copies_all() -> None:
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = []
    scanner = WorkerScanner(db, FakeLLM())

    asyncio.run(
        scanner.scan(_spec(criteria_changed=False, prev_run_id="prev-1"), "run-1", [])
    )

    cf_sql = _sql_body([s for n, s, _ in db.executes if n == "carry_forward"][0])
    assert "curation_type = 'manual'" not in cf_sql  # incremental → all rows


def test_no_carry_forward_on_first_run() -> None:
    db = RoutingFakeDb()
    db.rows["scan_candidates"] = []
    scanner = WorkerScanner(db, FakeLLM())

    asyncio.run(scanner.scan(_spec(prev_run_id=None), "run-1", []))

    assert "carry_forward" not in db.execute_names()  # nothing to carry
