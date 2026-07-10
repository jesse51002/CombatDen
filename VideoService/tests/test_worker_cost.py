"""WorkerCostLog — no DB (routed fake). Covers the three per-STEP log methods:
scrape (free search + tier-2 embed, keyed to a gym + run), enrich (POOL-LEVEL
transcript + enrich + embed rows with gym_id / run_id NULL — never the string
'None'), and scan (one row keyed to a gym + run)."""

from __future__ import annotations

import asyncio
import json

from schema.cost import CostStage
from src.worker.worker_config import settings
from src.worker.worker_cost_log import WorkerCostLog
from tests.worker_fakes import RoutingFakeDb


def _rows(db: RoutingFakeDb) -> list[dict]:
    return [p for n, _, p in db.writes if n == "insert_cost"]


def test_log_scrape_emits_free_search_and_embed() -> None:
    db = RoutingFakeDb()
    asyncio.run(
        WorkerCostLog(db).log_scrape(
            "gym-1", "run-1", youtube_quota_units=900, embed_usd=0.02
        )
    )

    by_stage = {p["stage"]: p for p in _rows(db)}
    assert set(by_stage) == {CostStage.search.value, CostStage.embed.value}

    search = by_stage[CostStage.search.value]
    assert search["cost_usd"] == 0.0 and search["model"] is None
    assert json.loads(search["breakdown"]) == {"youtube_quota_units": 900}

    embed = by_stage[CostStage.embed.value]
    assert embed["cost_usd"] == 0.02
    assert embed["model"] == settings.embedding_model
    # scrape rows are keyed to the gym + run.
    assert all(
        p["gym_id"] == "gym-1" and p["run_id"] == "run-1" for p in _rows(db)
    )
    assert all(p["source"] == "video" for p in _rows(db))


def test_log_enrich_rows_are_pool_level_null_keyed() -> None:
    db = RoutingFakeDb()
    asyncio.run(
        WorkerCostLog(db).log_enrich(
            transcript_usd=0.05,
            enrich_usd=0.20,
            embed_usd=0.02,
            videos=10,
            transcripts_fetched=3,
            actor_starts=2,
        )
    )

    by_stage = {p["stage"]: p for p in _rows(db)}
    assert set(by_stage) == {
        CostStage.transcript.value,
        CostStage.enrich.value,
        CostStage.embed.value,
    }
    # pool-level: gym_id / run_id are NULL — actual None, never the string 'None'.
    for p in _rows(db):
        assert p["gym_id"] is None
        assert p["run_id"] is None
        assert json.loads(p["breakdown"]) == {
            "videos": 10,
            "transcripts_fetched": 3,
            "actor_starts": 2,
        }

    assert by_stage[CostStage.transcript.value]["cost_usd"] == 0.05
    assert by_stage[CostStage.transcript.value]["model"] is None
    assert by_stage[CostStage.enrich.value]["model"] == settings.enrich_model
    assert by_stage[CostStage.embed.value]["model"] == settings.embedding_model


def test_log_scan_emits_one_row_keyed_to_gym_run() -> None:
    db = RoutingFakeDb()
    asyncio.run(
        WorkerCostLog(db).log_scan("gym-1", "run-1", scan_usd=0.30, scanned=12)
    )

    rows = _rows(db)
    assert len(rows) == 1
    row = rows[0]
    assert row["stage"] == CostStage.scan.value
    assert row["cost_usd"] == 0.30
    assert row["model"] == settings.scan_model
    assert row["gym_id"] == "gym-1" and row["run_id"] == "run-1"
    assert json.loads(row["breakdown"]) == {"llm_usd": 0.30, "scanned": 12}
