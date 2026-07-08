"""WorkerCostLog — no DB (routed fake). Covers the five per-stage rows: search is
free and carries its quota diagnostic; transcript carries the Apify spend; enrich
/ embed / scan carry their model + LLM spend; total_usd sums the billed stages."""

from __future__ import annotations

import asyncio
import json

import pytest

from schema.cost import CostStage
from src.worker.worker_cost_log import RunCost, WorkerCostLog
from tests.worker_fakes import RoutingFakeDb


def _cost() -> RunCost:
    return RunCost(
        search_usd=0.0,
        youtube_quota_units=900,
        transcript_usd=0.05,
        enrich_llm_usd=0.20,
        embed_usd=0.02,
        scan_llm_usd=0.30,
    )


def test_total_usd_sums_billed_stages() -> None:
    # Quota units are a diagnostic, not billed; search_usd is 0.
    assert _cost().total_usd == pytest.approx(0.57)


def test_log_emits_five_rows_incl_transcript() -> None:
    db = RoutingFakeDb()
    asyncio.run(WorkerCostLog(db).log("gym-1", "run-1", _cost()))

    rows = [p for n, _, p in db.writes if n == "insert_cost"]
    by_stage = {p["stage"]: p for p in rows}
    assert set(by_stage) == {
        CostStage.search.value,
        CostStage.transcript.value,
        CostStage.enrich.value,
        CostStage.embed.value,
        CostStage.scan.value,
    }

    search = by_stage[CostStage.search.value]
    assert search["cost_usd"] == 0.0
    assert search["model"] is None
    assert json.loads(search["breakdown"]) == {"youtube_quota_units": 900}

    transcript = by_stage[CostStage.transcript.value]
    assert transcript["cost_usd"] == 0.05
    assert transcript["model"] is None
    assert json.loads(transcript["breakdown"]) == {"apify_usd": 0.05}

    # Every row is stamped source='video' and the run/gym.
    assert all(p["source"] == "video" for p in rows)
    assert all(p["gym_id"] == "gym-1" and p["run_id"] == "run-1" for p in rows)
