"""WorkerEnricher — no DB, no network.

Covers: videos already in video_rag are skipped; a per-video failure is isolated
(the rest still enrich); the thumbnail is passed as image_urls only when it is a
plausible http(s) URL; and summaries embed in batches.
"""

from __future__ import annotations

import asyncio

from schema.gym_type import GymType
from schema.video_type import VideoType
from src.core.errors import ProviderError
from src.worker import worker_enricher
from src.worker.schema.enrich_result import EnrichResult
from src.worker.worker_enricher import WorkerEnricher
from tests.worker_fakes import FakeLLM, RoutingFakeDb


def _video(vid: str, *, thumbnail: str = "https://i.ytimg.com/x.jpg") -> dict:
    return {
        "video_id": vid,
        "title": f"Video {vid}",
        "channel_name": "Chan",
        "description": "desc",
        "thumbnail_url": thumbnail,
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


def test_skips_videos_already_in_rag() -> None:
    db = RoutingFakeDb()
    db.rows["owner_feed"] = []
    db.rows["existing_rag"] = [{"video_id": "v1"}]  # already enriched
    db.rows["load_videos_enrich"] = [_video("v2")]
    llm = FakeLLM(structured=_handler())
    enricher = WorkerEnricher(db, llm)

    result = asyncio.run(enricher.enrich("gym-1", ["v1", "v2"]))

    # Only the un-enriched id is loaded + enriched.
    assert db.read_params("load_videos_enrich")[0] == {"ids": ["v2"]}
    assert len(llm.structured_calls) == 1
    assert result.enriched_count == 1
    assert "update_tags" in db.write_names()
    assert "insert_rag" in db.write_names()


def test_per_video_failure_isolated() -> None:
    db = RoutingFakeDb()
    db.rows["load_videos_enrich"] = [_video("v1"), _video("v2")]
    llm = FakeLLM(structured=_handler(fail_substr="Video v1"))
    enricher = WorkerEnricher(db, llm)

    result = asyncio.run(enricher.enrich("gym-1", ["v1", "v2"]))

    assert result.enriched_count == 1 and result.skipped_count == 1
    tag_rows = [p for n, _, p in db.writes if n == "update_tags"][0]
    assert [r["video_id"] for r in tag_rows] == ["v2"]  # only the survivor
    rag_rows = [p for n, _, p in db.writes if n == "insert_rag"][0]
    assert [r["video_id"] for r in rag_rows] == ["v2"]


def test_image_urls_only_for_http_thumbnail() -> None:
    db = RoutingFakeDb()
    db.rows["load_videos_enrich"] = [
        _video("v1", thumbnail="https://img/a.jpg"),
        _video("v2", thumbnail=""),  # no usable thumbnail
    ]
    llm = FakeLLM(structured=_handler())
    enricher = WorkerEnricher(db, llm)

    asyncio.run(enricher.enrich("gym-1", ["v1", "v2"]))

    image_values = [c["image_urls"] for c in llm.structured_calls]
    assert ["https://img/a.jpg"] in image_values  # valid thumbnail attached
    assert None in image_values  # empty thumbnail → text-only call


def test_summaries_embed_in_batches(monkeypatch) -> None:
    monkeypatch.setattr(worker_enricher, "EMBED_BATCH_SIZE", 2)
    db = RoutingFakeDb()
    db.rows["load_videos_enrich"] = [_video("v1"), _video("v2"), _video("v3")]
    llm = FakeLLM(structured=_handler(cost=0.01), embed_cost=0.005)
    enricher = WorkerEnricher(db, llm)

    result = asyncio.run(enricher.enrich("gym-1", ["v1", "v2", "v3"]))

    assert result.enriched_count == 3
    assert len(llm.embed_calls) == 2  # 3 summaries in batches of 2 → 2 calls
    assert result.embed_usd == 0.01  # 0.005 × 2 batches
    rag_rows = [p for n, _, p in db.writes if n == "insert_rag"][0]
    assert len(rag_rows) == 3  # one video_rag row per enriched video
