"""Pure-logic unit tests for the video RAG read surface (no DB / no OpenAI).

Covers the deterministic genre→bucket map (asserted TOTAL both directions) and
the three services driven against a fake DB pool + fake litellm client:
``ensure_profile`` (build-if-missing vs no-op), ``refresh_if_due`` (cooldown
no-op vs stale rebuild), the member↔gym ownership guard (a mismatched / missing
member raises ``MemberNotInGymError`` before any build), ``load_embedding``,
the embedding-dimension guard, ``get_recs`` running ONE candidate query then
grouping by ``bucket_for_genre`` (honoring ``per_bucket`` + the ``record`` flag,
incl. the no-embedding degrade path), and ``search`` embedding the query once.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.video import MoodBucket, VideoGenre

from src.videos.schema.member_profile_schema import MemberProfileSummary
from src.videos.schema.video_mood_bucket import (
    GENRE_TO_BUCKET,
    bucket_for_genre,
    genres_for_bucket,
)
from src.videos.service.member_video_profile_service import (
    MemberNotInGymError,
    MemberVideoProfileService,
)
from src.videos.service.video_recs_service import VideoRecsService
from src.videos.service.video_search_service import VideoSearchService

# ── fake DB pool ─────────────────────────────────────────────────────


class _FakeResult:
    """A stand-in for a SQLAlchemy result: ``.mappings().all()/.fetchone()``."""

    def __init__(self, rows: list[dict] | None = None, one: dict | None = None):
        self._rows = rows or []
        self._one = one

    def mappings(self) -> _FakeResult:
        return self

    def all(self) -> list[dict]:
        return self._rows

    def fetchone(self) -> dict | None:
        return self._one


class _NullTxn:
    async def __aenter__(self) -> _NullTxn:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False


class _FakeSession:
    """Yields queued results in execute order; records each (sql, params)."""

    def __init__(self, results: list[_FakeResult]):
        self._results = list(results)
        self.executed: list[tuple[str, object]] = []

    async def __aenter__(self) -> _FakeSession:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False

    async def execute(self, sql: object, params: object = None) -> _FakeResult:
        self.executed.append((str(sql), params))
        return self._results.pop(0)

    def begin(self) -> _NullTxn:
        return _NullTxn()


def _make_pool(results: list[_FakeResult]) -> tuple[MagicMock, _FakeSession]:
    session = _FakeSession(results)
    pool = MagicMock()
    pool.session = lambda: session
    return pool, session


# ── genre → bucket map totality ──────────────────────────────────────


def test_genre_to_bucket_is_total_and_all_buckets_reachable() -> None:
    # Every genre maps to exactly one bucket.
    assert set(GENRE_TO_BUCKET) == set(VideoGenre)
    for genre in VideoGenre:
        assert isinstance(bucket_for_genre(genre), MoodBucket)
    # Every bucket is reachable, and the per-bucket genre lists partition the
    # full genre set (no genre missing, none double-counted).
    covered: list[VideoGenre] = []
    for bucket in MoodBucket:
        genres = genres_for_bucket(bucket)
        assert genres, f"bucket {bucket} has no genres"
        covered.extend(genres)
    assert sorted(g.value for g in covered) == sorted(
        g.value for g in VideoGenre
    )


def test_genre_to_bucket_exact_mapping() -> None:
    assert bucket_for_genre(VideoGenre.educational) is MoodBucket.teach
    assert bucket_for_genre(VideoGenre.analysis) is MoodBucket.teach
    assert bucket_for_genre(VideoGenre.entertainment) is MoodBucket.enjoy
    assert bucket_for_genre(VideoGenre.clips) is MoodBucket.enjoy
    assert bucket_for_genre(VideoGenre.memes) is MoodBucket.enjoy
    assert bucket_for_genre(VideoGenre.news) is MoodBucket.inform
    assert bucket_for_genre(VideoGenre.interview) is MoodBucket.human
    assert bucket_for_genre(VideoGenre.vlog) is MoodBucket.human
    assert bucket_for_genre(VideoGenre.professional) is MoodBucket.peak


# ── profile service fixtures ─────────────────────────────────────────


def _profile_service(
    pool: object, client: object, *, embedding_dim: int = 4
) -> MemberVideoProfileService:
    return MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=embedding_dim,
        summary_model="test/summary-model",
        refresh_cooldown_days=3,
    )


def _load_result(
    gym_id: object,
    *,
    embedding: str | None = None,
    built_at: datetime | None = None,
) -> _FakeResult:
    """A ``member_profile_load.sql`` row (or absent member when gym is None)."""
    if gym_id is None:
        return _FakeResult(one=None)
    return _FakeResult(
        one={
            "gym_id": str(gym_id),
            "video_profile_built_at": built_at,
            "video_profile_embedding_model": "test/model" if embedding else None,
            "embedding": embedding,
        }
    )


def _source_result(gym_id: object) -> _FakeResult:
    return _FakeResult(
        one={
            "gym_id": str(gym_id),
            "rank_name": "White Belt",
            "disciplines": ["bjj", "wrestling"],
            "attended_classes": ["BJJ Fundamentals"],
            "clicked_videos": [],
        }
    )


def _summary_client(*, dim: int = 4) -> MagicMock:
    client = MagicMock()
    client.complete_structured = AsyncMock(
        return_value=MemberProfileSummary(summary="loves bjj technique videos")
    )
    client.embed = AsyncMock(return_value=[[0.1] * dim])
    return client


# ── ensure_profile: build-if-missing vs no-op ────────────────────────


async def test_ensure_profile_builds_when_embedding_missing() -> None:
    gym_id = uuid4()
    pool, session = _make_pool(
        [
            _load_result(gym_id, embedding=None),  # load: no embedding yet
            _source_result(gym_id),  # source facts
            _FakeResult(),  # update
        ]
    )
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.ensure_profile(uuid4(), gym_id)

    client.complete_structured.assert_awaited_once()
    client.embed.assert_awaited_once()
    # load → source → update.
    assert len(session.executed) == 3
    update_params = session.executed[2][1]
    assert update_params["embedding"] == "[0.1,0.1,0.1,0.1]"
    assert update_params["summary"] == "loves bjj technique videos"


async def test_ensure_profile_noop_when_embedding_present() -> None:
    gym_id = uuid4()
    pool, session = _make_pool([_load_result(gym_id, embedding="[0.1,0.2]")])
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.ensure_profile(uuid4(), gym_id)

    client.complete_structured.assert_not_called()
    client.embed.assert_not_called()
    assert len(session.executed) == 1  # only the load ran


async def test_ensure_profile_raises_on_gym_mismatch() -> None:
    real_gym_id = uuid4()
    wrong_gym_id = uuid4()
    pool, session = _make_pool(
        [_load_result(real_gym_id, embedding=None)]
    )
    client = _summary_client()
    svc = _profile_service(pool, client)

    with pytest.raises(MemberNotInGymError, match="Member not found in this gym"):
        await svc.ensure_profile(uuid4(), wrong_gym_id)

    client.embed.assert_not_called()
    assert len(session.executed) == 1  # load only — no source, no build


async def test_ensure_profile_raises_when_member_missing() -> None:
    pool, session = _make_pool([_load_result(None)])
    client = _summary_client()
    svc = _profile_service(pool, client)

    with pytest.raises(MemberNotInGymError, match="Member not found in this gym"):
        await svc.ensure_profile(uuid4(), uuid4())

    client.embed.assert_not_called()
    assert len(session.executed) == 1


async def test_ensure_profile_raises_on_embedding_dim_mismatch() -> None:
    gym_id = uuid4()
    pool, _ = _make_pool(
        [_load_result(gym_id, embedding=None), _source_result(gym_id)]
    )
    client = _summary_client(dim=2)  # embed returns dim 2, service expects 4
    svc = _profile_service(pool, client)

    with pytest.raises(ValueError, match="embedding dimension"):
        await svc.ensure_profile(uuid4(), gym_id)


# ── refresh_if_due: cooldown no-op vs stale rebuild ──────────────────


async def test_refresh_if_due_noop_within_cooldown() -> None:
    gym_id = uuid4()
    fresh = datetime.now(UTC) - timedelta(days=1)  # < 3-day cooldown
    pool, session = _make_pool(
        [_load_result(gym_id, embedding="[0.1,0.2]", built_at=fresh)]
    )
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.refresh_if_due(uuid4(), gym_id)

    client.complete_structured.assert_not_called()
    client.embed.assert_not_called()
    assert len(session.executed) == 1  # load only


async def test_refresh_if_due_rebuilds_when_stale() -> None:
    gym_id = uuid4()
    stale = datetime.now(UTC) - timedelta(days=10)  # > 3-day cooldown
    pool, session = _make_pool(
        [
            _load_result(gym_id, embedding="[0.1,0.2]", built_at=stale),
            _source_result(gym_id),
            _FakeResult(),
        ]
    )
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.refresh_if_due(uuid4(), gym_id)

    client.complete_structured.assert_awaited_once()
    client.embed.assert_awaited_once()
    assert len(session.executed) == 3  # load → source → update


# ── load_embedding ───────────────────────────────────────────────────


async def test_load_embedding_returns_text_when_built() -> None:
    gym_id = uuid4()
    pool, _ = _make_pool([_load_result(gym_id, embedding="[0.3,0.4]")])
    svc = _profile_service(pool, _summary_client())

    assert await svc.load_embedding(uuid4()) == "[0.3,0.4]"


async def test_load_embedding_returns_none_when_absent() -> None:
    # No member row at all → None.
    pool, _ = _make_pool([_load_result(None)])
    svc = _profile_service(pool, _summary_client())
    assert await svc.load_embedding(uuid4()) is None


def test_as_list_tolerates_json_string_list_and_none() -> None:
    assert MemberVideoProfileService._as_list(None) == []
    assert MemberVideoProfileService._as_list('["a", "b"]') == ["a", "b"]
    assert MemberVideoProfileService._as_list(["a"]) == ["a"]


def test_render_prompt_degrades_gracefully_with_no_facts() -> None:
    svc = _profile_service(MagicMock(), _summary_client())
    prompt = svc._render_prompt(
        {
            "rank_name": None,
            "disciplines": [],
            "attended_classes": [],
            "clicked_videos": [],
        }
    )
    assert "an unranked member" in prompt
    assert "a fitness gym" in prompt
    assert "(none yet)" in prompt
    assert "$" not in prompt  # every placeholder substituted


# ── get_recs: one query, grouped by bucket ───────────────────────────


def _candidate_row(
    video_id: str = "vid1", tag: str = "educational", score: float = 0.9
) -> dict:
    return {
        "video_id": video_id,
        "url": f"https://youtu.be/{video_id}",
        "title": "Test",
        "thumbnail_url": "https://img/x.jpg",
        "channel_name": "Chan",
        "channel_url": "https://c",
        "channel_avatar_url": "",
        "view_count": 100,
        "duration_seconds": 60,
        "tag": tag,
        "relevance_index": 0,
        "already_recommended": False,
        "similarity": 0.8,
        "score": score,
    }


def _degrade_row(
    video_id: str = "vid1", tag: str = "educational", score: float = 0.5
) -> dict:
    """A no-embedding degrade candidate row — no ``similarity`` column."""
    row = _candidate_row(video_id, tag, score)
    del row["similarity"]
    return row


# One row per mood bucket (distinct genres) for the grouping tests.
_ONE_PER_BUCKET = [
    _candidate_row("vid_teach", "educational"),
    _candidate_row("vid_enjoy", "entertainment"),
    _candidate_row("vid_inform", "news"),
    _candidate_row("vid_human", "interview"),
    _candidate_row("vid_peak", "professional"),
]


def _recs_service(pool: MagicMock, profile: AsyncMock) -> VideoRecsService:
    return VideoRecsService(
        db_pool=pool,
        profile_service=profile,
        weight_similarity=0.7,
        weight_relevance=0.2,
        weight_views=0.1,
        candidate_limit=500,
    )


def _profile_stub(embedding: str | None = "[0.1]") -> AsyncMock:
    profile = AsyncMock()
    profile.ensure_profile = AsyncMock()
    profile.load_embedding = AsyncMock(return_value=embedding)
    return profile


async def test_get_recs_runs_one_query_and_groups_by_bucket() -> None:
    pool, session = _make_pool([_FakeResult(rows=list(_ONE_PER_BUCKET))])
    profile = _profile_stub()
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    profile.ensure_profile.assert_awaited_once()
    profile.load_embedding.assert_awaited_once()
    # ONE candidate query (rank-once) and NO record upsert (record=False).
    assert len(session.executed) == 1
    # The main (with-embedding) query bound the member embedding + w_sim.
    params = session.executed[0][1]
    assert params["member_embedding"] == "[0.1]"
    assert "w_sim" in params
    # All 5 buckets present, each with its one grouped video.
    assert len(resp.buckets) == len(MoodBucket)
    assert all(len(b.videos) == 1 for b in resp.buckets)


async def test_get_recs_honors_per_bucket_cap() -> None:
    # Three educational rows all map to teach; per_bucket=1 keeps only one.
    rows = [_candidate_row(f"e{i}", "educational") for i in range(3)]
    pool, session = _make_pool([_FakeResult(rows=rows)])
    profile = _profile_stub()
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=1, record=False)

    assert len(session.executed) == 1
    teach = next(b for b in resp.buckets if b.bucket is MoodBucket.teach)
    assert len(teach.videos) == 1
    assert all(
        len(b.videos) == 0 for b in resp.buckets if b.bucket is not MoodBucket.teach
    )


async def test_get_recs_records_served_when_record_true() -> None:
    pool, session = _make_pool(
        [_FakeResult(rows=list(_ONE_PER_BUCKET)), _FakeResult()]
    )
    profile = _profile_stub()
    svc = _recs_service(pool, profile)

    await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=True)

    # 1 candidate query + 1 record upsert.
    assert len(session.executed) == 2
    upsert_params = session.executed[1][1]
    assert isinstance(upsert_params, list) and len(upsert_params) == 5
    assert {p["video_id"] for p in upsert_params} == {
        r["video_id"] for r in _ONE_PER_BUCKET
    }


async def test_get_recs_degrades_when_no_embedding() -> None:
    # load_embedding → None → the no-embedding query runs; still all 5 buckets.
    pool, session = _make_pool(
        [_FakeResult(rows=[_degrade_row("d0", "educational")])]
    )
    profile = _profile_stub(embedding=None)
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    assert len(session.executed) == 1
    params = session.executed[0][1]
    # The degrade query binds NO similarity inputs.
    assert "member_embedding" not in params
    assert "w_sim" not in params
    assert len(resp.buckets) == len(MoodBucket)
    teach = next(b for b in resp.buckets if b.bucket is MoodBucket.teach)
    assert len(teach.videos) == 1


async def test_get_recs_propagates_member_not_in_gym() -> None:
    # The ownership guard is a hard 404 — get_recs never degrades it away.
    pool, session = _make_pool([])
    profile = AsyncMock()
    profile.ensure_profile = AsyncMock(
        side_effect=MemberNotInGymError("Member not found in this gym")
    )
    profile.load_embedding = AsyncMock()
    svc = _recs_service(pool, profile)

    with pytest.raises(MemberNotInGymError):
        await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    # No candidate query ran, and load_embedding was never reached.
    assert len(session.executed) == 0
    profile.load_embedding.assert_not_called()


async def test_get_recs_degrades_on_build_failure() -> None:
    # A profile-BUILD failure (LLM/embedding down) must not 500 — get_recs
    # swallows it and falls through to the no-embedding degrade ranking.
    pool, session = _make_pool(
        [_FakeResult(rows=[_degrade_row("d0", "educational")])]
    )
    profile = AsyncMock()
    profile.ensure_profile = AsyncMock(side_effect=RuntimeError("llm down"))
    profile.load_embedding = AsyncMock(return_value=None)
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    # Degrade query ran (no similarity inputs) and all 5 buckets are present.
    assert len(session.executed) == 1
    assert "member_embedding" not in session.executed[0][1]
    assert len(resp.buckets) == len(MoodBucket)


# ── search: embeds q once + dim guard ────────────────────────────────


def _search_row(video_id: str = "vid1", similarity: float = 0.7) -> dict:
    return {
        "video_id": video_id,
        "url": f"https://youtu.be/{video_id}",
        "title": "Test",
        "thumbnail_url": "https://img/x.jpg",
        "channel_name": "Chan",
        "channel_url": "https://c",
        "channel_avatar_url": "",
        "view_count": 100,
        "duration_seconds": 60,
        "tag": "educational",
        "relevance_index": 0,
        "similarity": similarity,
    }


async def test_search_embeds_query_once_and_forwards_limit() -> None:
    pool, session = _make_pool([_FakeResult(rows=[_search_row()])])
    client = MagicMock()
    client.embed = AsyncMock(return_value=[[0.1, 0.2, 0.3, 0.4]])
    svc = VideoSearchService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
    )

    results = await svc.search(uuid4(), "kettlebell swings", 20)

    client.embed.assert_awaited_once()
    _, kwargs = client.embed.call_args
    assert kwargs["texts"] == ["kettlebell swings"]
    assert len(results) == 1
    assert results[0].similarity == pytest.approx(0.7)
    assert session.executed[0][1]["limit"] == 20
    # Query embedding bound as pgvector text form.
    assert session.executed[0][1]["query_embedding"] == "[0.1,0.2,0.3,0.4]"


async def test_search_raises_on_embedding_dim_mismatch() -> None:
    pool, _ = _make_pool([])
    client = MagicMock()
    client.embed = AsyncMock(return_value=[[0.1, 0.2]])  # dim 2 != 4
    svc = VideoSearchService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
    )

    with pytest.raises(ValueError, match="embedding dimension"):
        await svc.search(uuid4(), "q", 20)
