"""WorkerEnricher global sweep — no DB, no network.

Covers: the sweep drains ``worker_enrich_targets`` (scoped by the strike-max bind);
a per-video multimodal failure is isolated AND struck (the rest still enrich); the
thumbnail is passed as image_urls only for a plausible http(s) URL; summaries embed
in per-chunk batches; an embed failure strikes the whole chunk; the LAZY transcript
fetch (used in the prompt + cached back + billed, not re-fetched when cached, miss
degrades to the placeholder and is NOT a strike); a success resets the strike
counter; and pool-level enrich cost is logged once.
"""

from __future__ import annotations

import asyncio

from schema.gym_type import GymType
from schema.video_type import VideoType
from src.core.errors import ProviderError
from src.worker import worker_enricher
from src.worker.schema.enrich_result import EnrichResult
from src.worker.worker_config import settings
from src.worker.worker_enricher import NO_TRANSCRIPT_PLACEHOLDER, WorkerEnricher
from tests.worker_fakes import FakeLLM, FakeTranscriptClient, RoutingFakeDb


class FakeCostLog:
    def __init__(self) -> None:
        self.enrich: list[dict] = []

    async def log_enrich(self, **kwargs: object) -> None:
        self.enrich.append(dict(kwargs))


def _abort() -> asyncio.Event:
    return asyncio.Event()  # never set


def _enricher(db, llm, transcript):
    cost = FakeCostLog()
    return WorkerEnricher(db, llm, transcript, cost), cost


def _video(
    vid: str,
    *,
    thumbnail: str = "https://i.ytimg.com/x.jpg",
    transcript: str | None = "a transcript",
) -> dict:
    return {
        "video_id": vid,
        "title": f"Video {vid}",
        "channel_name": "Chan",
        "description": "desc",
        "thumbnail_url": thumbnail,
        "duration_seconds": 120,
        "transcript": transcript,
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


def _writes(db: RoutingFakeDb, name: str) -> list:
    return [p for n, _, p in db.writes if n == name]


def test_empty_targets_is_noop() -> None:
    db = RoutingFakeDb()  # enrich_targets → []
    llm = FakeLLM(structured=_handler())
    enricher, cost = _enricher(db, llm, FakeTranscriptClient())

    did_work = asyncio.run(enricher.drain(_abort()))

    assert did_work is False
    assert llm.structured_calls == []
    assert cost.enrich == []  # nothing swept → no cost row


def test_targets_query_scoped_by_strike_max() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1")]
    llm = FakeLLM(structured=_handler())
    enricher, _ = _enricher(db, llm, FakeTranscriptClient())

    asyncio.run(enricher.drain(_abort()))

    # the target set (accepted-without-rag ∪ owner ∪ pending, minus enriched) is
    # the SQL's job; the sweep only binds the strike ceiling.
    assert db.read_params("enrich_targets")[0] == {
        "max_failures": settings.worker_failure_max
    }


def test_success_enriches_and_resets_strikes() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v2")]
    llm = FakeLLM(structured=_handler())
    enricher, cost = _enricher(db, llm, FakeTranscriptClient())

    did_work = asyncio.run(enricher.drain(_abort()))

    assert did_work is True
    assert len(llm.structured_calls) == 1
    assert "update_tags" in db.write_names()
    assert "insert_rag" in db.write_names()
    # a successful enrich clears the video's strike counter, never bumps it.
    assert [r["video_id"] for r in _writes(db, "reset_failure")[0]] == ["v2"]
    assert "bump_failure" not in db.write_names()
    assert len(cost.enrich) == 1  # pool-level cost logged once


def test_per_video_failure_isolated_and_struck() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1"), _video("v2")]
    llm = FakeLLM(structured=_handler(fail_substr="Video v1"))
    enricher, _ = _enricher(db, llm, FakeTranscriptClient())

    asyncio.run(enricher.drain(_abort()))

    assert [r["video_id"] for r in _writes(db, "update_tags")[0]] == ["v2"]
    assert [r["video_id"] for r in _writes(db, "insert_rag")[0]] == ["v2"]
    assert [r["video_id"] for r in _writes(db, "reset_failure")[0]] == ["v2"]
    # the hard-failed video is struck (a strike, not a silent skip).
    assert [r["video_id"] for r in _writes(db, "bump_failure")[0]] == ["v1"]


def test_image_urls_only_for_http_thumbnail() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [
        _video("v1", thumbnail="https://img/a.jpg"),
        _video("v2", thumbnail=""),  # no usable thumbnail
    ]
    llm = FakeLLM(structured=_handler())
    enricher, _ = _enricher(db, llm, FakeTranscriptClient())

    asyncio.run(enricher.drain(_abort()))

    image_values = [c["image_urls"] for c in llm.structured_calls]
    assert ["https://img/a.jpg"] in image_values  # valid thumbnail attached
    assert None in image_values  # empty thumbnail → text-only call


def test_summaries_embed_in_batches(monkeypatch) -> None:
    monkeypatch.setattr(worker_enricher, "EMBED_BATCH_SIZE", 2)
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1"), _video("v2"), _video("v3")]
    llm = FakeLLM(structured=_handler(cost=0.01), embed_cost=0.005)
    enricher, cost = _enricher(db, llm, FakeTranscriptClient())

    did_work = asyncio.run(enricher.drain(_abort()))

    assert did_work is True
    # 3 targets in chunks of 2 → one embed call per chunk = 2 embed calls.
    assert len(llm.embed_calls) == 2
    total_rag = sum(len(p) for p in _writes(db, "insert_rag"))
    assert total_rag == 3  # one video_rag row per enriched video
    assert cost.enrich[0]["embed_usd"] == 0.01  # 0.005 × 2 chunks


def test_embed_failure_strikes_chunk() -> None:
    class EmbedFailLLM(FakeLLM):
        async def embed(self, texts, model):  # noqa: ANN001
            raise ProviderError("embed down")

    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1")]
    llm = EmbedFailLLM(structured=_handler())
    enricher, _ = _enricher(db, llm, FakeTranscriptClient())

    asyncio.run(enricher.drain(_abort()))

    # the multimodal call succeeded (tags written) but the embed raised, so the
    # chunk's video is struck and never gets a video_rag row.
    assert "insert_rag" not in db.write_names()
    assert [r["video_id"] for r in _writes(db, "bump_failure")[0]] == ["v1"]
    assert "reset_failure" not in db.write_names()


def test_lazy_fetch_used_cached_and_billed() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1", transcript=None)]  # no transcript
    transcript = FakeTranscriptClient({"v1": "the fetched transcript body"})
    llm = FakeLLM(structured=_handler())
    enricher, cost = _enricher(db, llm, transcript)

    asyncio.run(enricher.drain(_abort()))

    assert transcript.fetched == ["v1"]
    prompt = llm.structured_calls[0]["messages"][0]["content"]
    assert "the fetched transcript body" in prompt
    cache_rows = _writes(db, "cache_transcripts")[0]
    assert cache_rows == [
        {"video_id": "v1", "transcript": "the fetched transcript body"}
    ]
    assert cost.enrich[0]["transcript_usd"] == round(
        settings.apify_transcript_cost_per_video_usd, 4
    )
    assert cost.enrich[0]["transcripts_fetched"] == 1


def test_cached_transcript_not_refetched() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1", transcript="already have it")]
    transcript = FakeTranscriptClient({"v1": "should not be used"})
    llm = FakeLLM(structured=_handler())
    enricher, cost = _enricher(db, llm, transcript)

    asyncio.run(enricher.drain(_abort()))

    assert transcript.fetched == []  # never fetched — the row already had one
    assert "cache_transcripts" not in db.write_names()
    assert cost.enrich[0]["transcript_usd"] == 0.0
    assert "already have it" in llm.structured_calls[0]["messages"][0]["content"]


def test_fetch_miss_degrades_to_placeholder_not_a_strike() -> None:
    db = RoutingFakeDb()
    db.rows["enrich_targets"] = [_video("v1", transcript=None)]
    transcript = FakeTranscriptClient(fail=True)  # every fetch misses
    llm = FakeLLM(structured=_handler())
    enricher, cost = _enricher(db, llm, transcript)

    asyncio.run(enricher.drain(_abort()))

    assert transcript.fetched == ["v1"]  # the fetch was attempted
    prompt = llm.structured_calls[0]["messages"][0]["content"]
    assert NO_TRANSCRIPT_PLACEHOLDER in prompt  # degraded to the placeholder
    assert "cache_transcripts" not in db.write_names()  # nothing to cache
    # a missing transcript is NOT a strike — the enrich still succeeded.
    assert "bump_failure" not in db.write_names()
    assert [r["video_id"] for r in _writes(db, "reset_failure")[0]] == ["v1"]
    # a missed fetch still ran the actor → still billed.
    assert cost.enrich[0]["transcript_usd"] == round(
        settings.apify_transcript_cost_per_video_usd, 4
    )
