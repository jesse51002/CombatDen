"""enrich-templates sidecar + runner — no DB, no network, no provider keys.

Covers the RAG sidecar's append/read round-trip (incl. the float32 embedding pack
and a tolerated corrupt trailing line) and the runner's reuse of the worker
enricher's per-video unit: it enriches only the not-yet-in-sidecar targets, embeds
each summary, appends a record per success, isolates a per-video failure, and is
resumable (a second run over the same sidecar does nothing).
"""

from __future__ import annotations

import asyncio

import pytest

from schema.gym_type import GymType
from schema.video_type import VideoType
from src.core.errors import ProviderError
from src.worker.schema.enrich_result import EnrichResult
from src.worker.worker_config import settings
from src.worker.worker_enricher import WorkerEnricher
from tests.worker_fakes import FakeLLM, FakeTranscriptClient

from scripts.enrich_templates.run import EnrichTemplatesRunner
from scripts.shared.video_rag_sidecar import VideoRagRecord, VideoRagSidecar


# --- sidecar --------------------------------------------------------------------


def _record(vid: str, embedding: list[float]) -> VideoRagRecord:
    return VideoRagRecord(
        video_id=vid,
        summary=f"summary {vid}",
        tag="educational",
        disciplines=["mma", "bjj"],
        facets={"gi": True, "level": "beginner"},
        embedding=embedding,
        embedding_model="openai/text-embedding-3-small",
    )


def test_sidecar_round_trip(tmp_path) -> None:
    sidecar = VideoRagSidecar(tmp_path)
    # float32-exact values so the packed round-trip compares equal.
    records = [_record("v1", [1.0, -0.5, 0.25]), _record("v2", [0.125, 0.0, -1.0])]
    sidecar.append(records)

    back = list(sidecar.read_all())
    assert [r.video_id for r in back] == ["v1", "v2"]
    assert back[0].summary == "summary v1"
    assert back[0].disciplines == ["mma", "bjj"]
    assert back[0].facets == {"gi": True, "level": "beginner"}
    assert back[0].embedding == [1.0, -0.5, 0.25]
    assert back[1].embedding == [0.125, 0.0, -1.0]
    assert sidecar.existing_ids() == {"v1", "v2"}


def test_embedding_pack_is_float32_lossless_within_tolerance() -> None:
    vec = [0.1, 0.2, -0.333333, 42.5]
    decoded = VideoRagSidecar.decode_embedding(VideoRagSidecar.encode_embedding(vec))
    assert decoded == pytest.approx(vec, rel=1e-6)


def test_to_pgvector_literal() -> None:
    assert VideoRagSidecar.to_pgvector([1.0, -0.5]).startswith("[")
    assert VideoRagSidecar.to_pgvector([1.0, -0.5]).endswith("]")
    assert VideoRagSidecar.to_pgvector([]) == "[]"


def test_corrupt_trailing_line_tolerated(tmp_path) -> None:
    sidecar = VideoRagSidecar(tmp_path)
    sidecar.append([_record("v1", [1.0, 2.0])])
    # simulate a crash mid-write: a garbage partial line at the end.
    with sidecar.path.open("a", encoding="utf-8") as handle:
        handle.write('{"video_id": "v2", "summary": "trunc')
    assert sidecar.existing_ids() == {"v1"}  # partial line skipped
    assert [r.video_id for r in sidecar.read_all()] == ["v1"]


def test_empty_append_writes_no_file(tmp_path) -> None:
    sidecar = VideoRagSidecar(tmp_path)
    sidecar.append([])
    assert not sidecar.exists()
    assert sidecar.existing_ids() == set()


# --- runner ---------------------------------------------------------------------


class _FakeDb:
    """Minimal DirectDatabasePool stand-in: fetch_all returns canned target rows."""

    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows

    async def fetch_all(self, sql: str, params=None) -> list[dict]:  # noqa: ANN001
        return list(self._rows)


class _NoopCostLog:
    """WorkerEnricher requires a cost log; enrich_one never calls it."""


def _video(vid: str) -> dict:
    return {
        "video_id": vid,
        "title": f"Video {vid}",
        "channel_name": "Chan",
        "description": "desc",
        "thumbnail_url": "https://i.ytimg.com/x.jpg",
        "duration_seconds": 120,
        "transcript": "a transcript",
    }


def _ok_result() -> EnrichResult:
    return EnrichResult(
        tag=VideoType.EDUCATIONAL,
        disciplines=[GymType.MMA],
        summary="a gi bjj demo in a studio",
        facets={"gi": True},
    )


def _handler(fail_substr: str | None = None, cost: float = 0.02):
    def handler(call: dict) -> tuple[EnrichResult, float]:
        prompt = call["messages"][0]["content"]
        if fail_substr is not None and fail_substr in prompt:
            raise ProviderError("enrich boom")
        return _ok_result(), cost

    return handler


def _runner(db, llm, sidecar) -> EnrichTemplatesRunner:  # noqa: ANN001
    enricher = WorkerEnricher(db, llm, FakeTranscriptClient(), _NoopCostLog())
    return EnrichTemplatesRunner(db, enricher, llm, sidecar)


def test_runner_enriches_and_writes_sidecar(tmp_path) -> None:
    db = _FakeDb([_video("v1"), _video("v2")])
    llm = FakeLLM(structured=_handler(), embed_cost=0.001, embed_dim=3)
    sidecar = VideoRagSidecar(tmp_path)

    totals = asyncio.run(_runner(db, llm, sidecar).run())

    assert totals.processed == 2
    assert totals.enriched == 2
    assert totals.failed == 0
    assert totals.enrich_usd == pytest.approx(0.04)  # 0.02 × 2
    assert totals.embed_usd == pytest.approx(0.001)  # one embed call for the chunk
    records = list(sidecar.read_all())
    assert {r.video_id for r in records} == {"v1", "v2"}
    assert records[0].summary == "a gi bjj demo in a studio"
    assert records[0].tag == "educational"
    assert records[0].disciplines == ["mma"]
    assert records[0].embedding_model == settings.embedding_model
    assert len(records[0].embedding) == 3  # FakeLLM embed_dim


def test_runner_skips_already_enriched(tmp_path) -> None:
    sidecar = VideoRagSidecar(tmp_path)
    llm = FakeLLM(structured=_handler(), embed_dim=3)
    # first run enriches both
    asyncio.run(_runner(_FakeDb([_video("v1"), _video("v2")]), llm, sidecar).run())
    # second run over the SAME sidecar: both are done → no work
    totals = asyncio.run(
        _runner(_FakeDb([_video("v1"), _video("v2")]), llm, sidecar).run()
    )
    assert totals.processed == 0
    assert totals.enriched == 0
    assert len(list(sidecar.read_all())) == 2  # unchanged, not duplicated


def test_runner_isolates_a_failed_video(tmp_path) -> None:
    db = _FakeDb([_video("v1"), _video("v2")])
    llm = FakeLLM(structured=_handler(fail_substr="Video v1"), embed_dim=3)
    sidecar = VideoRagSidecar(tmp_path)

    totals = asyncio.run(_runner(db, llm, sidecar).run())

    assert totals.processed == 2
    assert totals.enriched == 1
    assert totals.failed == 1
    # only the success is persisted; v1 is re-attempted on a later run.
    assert [r.video_id for r in sidecar.read_all()] == ["v2"]
