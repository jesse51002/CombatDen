"""WorkerScanner global sweep — no DB, no network.

Covers: the sweep drains ``worker_scan_targets`` grouped by gym; judges against the
gym's LATEST spec (read at scan time); batches by ``scan_batch_size``; writes
verdicts by UPDATE (guarded on ``scan_status = 'pending'``); resets strikes on a
verdict; strikes-without-reject on failure (a batch LLM exception bumps every video
in the batch and leaves them pending; a per-id omission bumps that id alone, still
pending — NO default-to-rejected); drops hallucinated ids; passes thumbnails as
image_urls in candidate order; stamps rejected_at only on rejects; and logs one
scan cost row per gym.
"""

from __future__ import annotations

import asyncio
import re

from src.core.errors import ProviderError
from src.worker import worker_config
from src.worker.schema.scan_batch import ScanBatchResult, ScanVerdictItem
from src.worker.worker_scanner import WorkerScanner
from tests.worker_fakes import FakeLLM, RoutingFakeDb


class FakeCostLog:
    def __init__(self) -> None:
        self.scans: list[tuple] = []

    async def log_scan(self, gym_id, run_id, *, scan_usd, scanned):  # noqa: ANN001
        self.scans.append((gym_id, run_id, scan_usd, scanned))


def _abort() -> asyncio.Event:
    return asyncio.Event()  # never set


def _scanner(db, llm):
    cost = FakeCostLog()
    return WorkerScanner(db, llm, cost), cost


def _candidate(
    vid: str,
    *,
    gym_id: str = "gym-1",
    run_id: str = "run-1",
    thumbnail: str = "https://i.ytimg.com/x.jpg",
) -> dict:
    return {
        "gym_id": gym_id,
        "video_run_id": run_id,
        "video_id": vid,
        "title": f"Title {vid}",
        "channel_name": "Chan",
        "thumbnail_url": thumbnail,
        "genre": "educational",
        "summary": "summary text",
    }


def _criteria() -> dict:
    return {"videos_desc": "worth surfacing", "avoid_desc": "avoid"}


def _handler(
    good: set[str],
    *,
    omit: set[str] = frozenset(),
    hallucinate: bool = False,
    cost: float = 0.05,
):
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
    lists = [p for n, _, p in db.writes if n == "update_verdict"]
    return [row for batch in lists for row in batch]


def _struck(db: RoutingFakeDb) -> set[str]:
    lists = [p for n, _, p in db.writes if n == "bump_failure"]
    return {row["video_id"] for batch in lists for row in batch}


def _reset(db: RoutingFakeDb) -> set[str]:
    lists = [p for n, _, p in db.writes if n == "reset_failure"]
    return {row["video_id"] for batch in lists for row in batch}


def test_empty_targets_is_noop() -> None:
    db = RoutingFakeDb()  # scan_targets → []
    llm = FakeLLM(structured=_handler(set()))
    scanner, cost = _scanner(db, llm)

    did_work = asyncio.run(scanner.drain(_abort()))

    assert did_work is False
    assert llm.structured_calls == []
    assert cost.scans == []


def test_batch_splitting_and_verdicts(monkeypatch) -> None:
    monkeypatch.setattr(worker_config.settings, "scan_batch_size", 2)
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [
        _candidate("a"), _candidate("b"), _candidate("c")
    ]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a", "b", "c"}))
    scanner, cost = _scanner(db, llm)

    did_work = asyncio.run(scanner.drain(_abort()))

    assert did_work is True
    assert len(llm.structured_calls) == 2  # 3 candidates in batches of 2
    assert {r["video_id"] for r in _verdict_rows(db)} == {"a", "b", "c"}
    assert all(r["verdict"] == "accepted" for r in _verdict_rows(db))
    assert _reset(db) == {"a", "b", "c"}  # verdicted → strikes cleared
    assert "bump_failure" not in db.write_names()
    assert cost.scans == [("gym-1", "run-1", 0.10, 3)]  # 0.05 × 2 batches


def test_verdict_update_is_pending_guarded() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [_candidate("a")]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a"}))
    scanner, _ = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    verdict_sql = [s for n, s, _ in db.writes if n == "update_verdict"][0]
    # the guard is what stops a manual / prior verdict being overwritten.
    assert "scan_status = 'pending'" in verdict_sql
    row = _verdict_rows(db)[0]
    assert row["gym_id"] == "gym-1" and row["video_run_id"] == "run-1"


def test_batch_exception_strikes_all_stays_pending() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [_candidate("a"), _candidate("b")]
    db.ones["spec_latest"] = _criteria()

    def boom(call: dict) -> tuple[ScanBatchResult, float]:
        raise ProviderError("scan down")

    scanner, cost = _scanner(db, FakeLLM(structured=boom))

    asyncio.run(scanner.drain(_abort()))

    # NO default-to-rejected: no verdict is written; every batch video is struck
    # and left pending; cost is 0 for the failed batch.
    assert "update_verdict" not in db.write_names()
    assert _struck(db) == {"a", "b"}
    assert "reset_failure" not in db.write_names()
    assert cost.scans == [("gym-1", "run-1", 0.0, 2)]


def test_missing_verdict_bumps_only_those_stays_pending() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [_candidate("a"), _candidate("b")]
    db.ones["spec_latest"] = _criteria()
    # 'b' gets no verdict from the model; there is no retry and no default-reject.
    llm = FakeLLM(structured=_handler({"a"}, omit={"b"}))
    scanner, _ = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    assert len(llm.structured_calls) == 1  # no retry pass anymore
    verdicts = {r["video_id"]: r for r in _verdict_rows(db)}
    assert set(verdicts) == {"a"}  # only 'a' is verdicted
    assert verdicts["a"]["verdict"] == "accepted"
    assert _struck(db) == {"b"}  # 'b' struck, left pending (NOT rejected)
    assert _reset(db) == {"a"}


def test_hallucinated_ids_dropped() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [_candidate("a")]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a"}, hallucinate=True))
    scanner, _ = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    assert {r["video_id"] for r in _verdict_rows(db)} == {"a"}  # ZZZ dropped


def test_rejected_stamps_rejected_at() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [_candidate("a"), _candidate("b")]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a"}))  # 'a' good, 'b' rejected
    scanner, _ = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    rows = {r["video_id"]: r for r in _verdict_rows(db)}
    assert rows["a"]["verdict"] == "accepted" and rows["a"]["rejected_at"] is None
    assert rows["b"]["verdict"] == "rejected"
    assert rows["b"]["rejected_at"] is not None


def test_multimodal_image_order() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [
        _candidate("a", thumbnail="https://a.jpg"),
        _candidate("b", thumbnail=""),  # no image
        _candidate("c", thumbnail="https://c.jpg"),
    ]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a", "b", "c"}))
    scanner, _ = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    call = llm.structured_calls[0]
    # images are in candidate order, skipping the no-image candidate.
    assert call["image_urls"] == ["https://a.jpg", "https://c.jpg"]
    prompt = call["messages"][0]["content"]
    assert "(no image provided)" in prompt  # 'b' noted, not dropped
    assert "worth surfacing" in prompt  # latest spec criteria in the prompt


def test_per_gym_spec_and_cost() -> None:
    db = RoutingFakeDb()
    db.rows["scan_targets"] = [
        _candidate("a", gym_id="g1", run_id="r1"),
        _candidate("b", gym_id="g2", run_id="r2"),
    ]
    db.ones["spec_latest"] = _criteria()
    llm = FakeLLM(structured=_handler({"a", "b"}))
    scanner, cost = _scanner(db, llm)

    asyncio.run(scanner.drain(_abort()))

    # spec loaded once per gym; one scan cost row per gym keyed to its run.
    assert len(db.read_params("spec_latest")) == 2
    assert ("g1", "r1", 0.05, 1) in cost.scans
    assert ("g2", "r2", 0.05, 1) in cost.scans
