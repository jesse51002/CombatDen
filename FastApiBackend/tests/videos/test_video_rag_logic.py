"""Pure-logic unit tests for the video RAG read surface (no DB / no OpenAI).

Covers the deterministic genre→bucket map (asserted TOTAL both directions), the
deterministic profile-text template (incl. NULL-rank / zero-attendance
branches), and the three services driven against a fake DB pool + fake litellm
client: ``ensure_profiles`` freshness (no-op vs rebuild), the member↔gym
ownership guard on both the fresh and cold-build paths (a mismatched gym_id
raises ``ValueError`` before any profile build), ``get_recs`` running one
query per bucket and honoring the ``record`` flag, ``search`` embedding the
query once, and the embedding-dimension guard raising on a mismatch.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.video import MoodBucket, VideoGenre

from src.videos.schema.video_mood_bucket import (
    GENRE_TO_BUCKET,
    bucket_for_genre,
    genres_for_bucket,
)
from src.videos.service.member_video_profile_service import (
    ATTENDANCE_WINDOW_DAYS,
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


# ── deterministic profile template ───────────────────────────────────


def _profile_service(embedding_dim: int = 4) -> MemberVideoProfileService:
    return MemberVideoProfileService(
        db_pool=MagicMock(),
        litellm_client=MagicMock(),
        embedding_model="test/model",
        embedding_dim=embedding_dim,
        profile_ttl_days=30,
    )


def test_profile_text_full_is_deterministic_and_shaped() -> None:
    svc = _profile_service()
    source = {
        "rank_main_name": "White",
        "rank_sub_name": "0 stripes",
        "attendance_count": 7,
        "top_classes": ["BJJ Fundamentals", "Wrestling"],
        "disciplines": ["bjj", "wrestling"],
    }
    texts = svc._build_texts(source)
    # Deterministic: same input → identical output.
    assert svc._build_texts(source) == texts
    # All five buckets present.
    assert set(texts) == set(MoodBucket)
    base = (
        "A White 0 stripes member at a bjj, wrestling gym, attended 7 classes "
        f"in the last {ATTENDANCE_WINDOW_DAYS} days, mostly BJJ Fundamentals, "
        "Wrestling."
    )
    assert texts[MoodBucket.teach] == (
        f"{base} This member wants technique tutorials, drills and "
        "progress-appropriate instruction."
    )
    assert "elite professional performances" in texts[MoodBucket.peak]
    assert texts[MoodBucket.peak].startswith(base)


def test_profile_text_null_rank_becomes_a_member() -> None:
    svc = _profile_service()
    source = {
        "rank_main_name": None,
        "rank_sub_name": None,
        "attendance_count": 3,
        "top_classes": ["Boxing"],
        "disciplines": ["boxing"],
    }
    texts = svc._build_texts(source)
    assert texts[MoodBucket.enjoy].startswith(
        "A member at a boxing gym, attended 3 classes"
    )
    assert "None" not in texts[MoodBucket.enjoy]


def test_profile_text_zero_attendance_omits_clause() -> None:
    svc = _profile_service()
    source = {
        "rank_main_name": "Blue",
        "rank_sub_name": "2 stripes",
        "attendance_count": 0,
        "top_classes": [],
        "disciplines": [],
    }
    texts = svc._build_texts(source)
    base = texts[MoodBucket.peak].split(" This member")[0]
    # No attendance clause, and no disciplines → "at a gym".
    assert base == "A Blue 2 stripes member at a gym."
    assert "attended" not in base


def test_as_list_tolerates_json_string_list_and_none() -> None:
    assert MemberVideoProfileService._as_list(None) == []
    assert MemberVideoProfileService._as_list('["a", "b"]') == ["a", "b"]
    assert MemberVideoProfileService._as_list(["a"]) == ["a"]


# ── ensure_profiles: freshness (no-op vs rebuild) ────────────────────


def _profile_rows(built_at: datetime, gym_id: object) -> list[dict]:
    return [
        {"bucket": b.value, "built_at": built_at, "gym_id": str(gym_id)}
        for b in MoodBucket
    ]


async def test_ensure_profiles_noop_when_fresh() -> None:
    gym_id = uuid4()
    pool, session = _make_pool(
        [_FakeResult(rows=_profile_rows(datetime.now(UTC), gym_id))]
    )
    client = MagicMock()
    client.embed = AsyncMock()
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    await svc.ensure_profiles(uuid4(), gym_id)

    client.embed.assert_not_called()
    # Only the freshness load ran — no source read, no upsert.
    assert len(session.executed) == 1


async def test_ensure_profiles_rebuilds_when_stale() -> None:
    gym_id = uuid4()
    stale = datetime.now(UTC) - timedelta(days=60)
    source_row = {
        "gym_id": str(gym_id),
        "rank_main_name": "White",
        "rank_sub_name": "0 stripes",
        "attendance_count": 2,
        "top_classes": ["BJJ"],
        "disciplines": ["bjj"],
    }
    pool, session = _make_pool(
        [
            _FakeResult(rows=_profile_rows(stale, gym_id)),  # load (stale)
            _FakeResult(one=source_row),  # source
            _FakeResult(),  # upsert
        ]
    )
    client = MagicMock()
    client.embed = AsyncMock(
        return_value=[[0.1, 0.2, 0.3, 0.4] for _ in range(5)]
    )
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    await svc.ensure_profiles(uuid4(), gym_id)

    client.embed.assert_awaited_once()
    # load → source → upsert.
    assert len(session.executed) == 3
    upsert_params = session.executed[2][1]
    assert isinstance(upsert_params, list) and len(upsert_params) == 5
    # Embedding serialized to pgvector text form.
    assert upsert_params[0]["embedding"] == "[0.1,0.2,0.3,0.4]"


async def test_ensure_profiles_rebuilds_when_buckets_missing() -> None:
    gym_id = uuid4()
    fresh = datetime.now(UTC)
    partial = [
        {"bucket": MoodBucket.teach.value, "built_at": fresh, "gym_id": str(gym_id)}
    ]
    source_row = {
        "gym_id": str(gym_id),
        "rank_main_name": None,
        "rank_sub_name": None,
        "attendance_count": 0,
        "top_classes": [],
        "disciplines": [],
    }
    pool, session = _make_pool(
        [
            _FakeResult(rows=partial),  # only 1 of 5 buckets → rebuild
            _FakeResult(one=source_row),
            _FakeResult(),
        ]
    )
    client = MagicMock()
    client.embed = AsyncMock(
        return_value=[[0.5, 0.6, 0.7, 0.8] for _ in range(5)]
    )
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    await svc.ensure_profiles(uuid4(), gym_id)
    client.embed.assert_awaited_once()
    assert len(session.executed) == 3


async def test_ensure_profiles_raises_on_embedding_dim_mismatch() -> None:
    gym_id = uuid4()
    stale = datetime.now(UTC) - timedelta(days=60)
    source_row = {
        "gym_id": str(gym_id),
        "rank_main_name": None,
        "rank_sub_name": None,
        "attendance_count": 0,
        "top_classes": [],
        "disciplines": [],
    }
    pool, _ = _make_pool(
        [
            _FakeResult(rows=_profile_rows(stale, gym_id)),
            _FakeResult(one=source_row),
        ]
    )
    client = MagicMock()
    client.embed = AsyncMock(return_value=[[0.1, 0.2] for _ in range(5)])  # dim 2
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,  # expects 4, gets 2
        profile_ttl_days=30,
    )

    with pytest.raises(ValueError, match="embedding dimension"):
        await svc.ensure_profiles(uuid4(), gym_id)


# ── ensure_profiles: member↔gym ownership guard (security) ──────────


async def test_ensure_profiles_raises_when_fresh_profile_belongs_to_different_gym() -> (
    None
):
    """A member with already-fresh profiles built under their REAL gym must
    still be rejected when asked about a DIFFERENT gym_id — otherwise an
    authorized viewer could pass a mismatched gym_id and rank that other
    gym's feed against the real member's profile. No source read, no build."""
    real_gym_id = uuid4()
    wrong_gym_id = uuid4()
    pool, session = _make_pool(
        [_FakeResult(rows=_profile_rows(datetime.now(UTC), real_gym_id))]
    )
    client = MagicMock()
    client.embed = AsyncMock()
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    with pytest.raises(ValueError, match="Member not found in this gym"):
        await svc.ensure_profiles(uuid4(), wrong_gym_id)

    client.embed.assert_not_called()
    # Only the freshness load ran — no source read, no upsert, no build.
    assert len(session.executed) == 1


async def test_ensure_profiles_raises_when_member_in_different_gym_cold_path() -> None:
    """No profile rows yet (first-ever request): the cold-build path's own
    guard reads the live member row and rejects a mismatched gym_id before
    any embedding call."""
    real_gym_id = uuid4()
    wrong_gym_id = uuid4()
    source_row = {
        "gym_id": str(real_gym_id),
        "rank_main_name": None,
        "rank_sub_name": None,
        "attendance_count": 0,
        "top_classes": [],
        "disciplines": [],
    }
    pool, session = _make_pool(
        [
            _FakeResult(rows=[]),  # no profiles yet
            _FakeResult(one=source_row),  # source: member is in a DIFFERENT gym
        ]
    )
    client = MagicMock()
    client.embed = AsyncMock()
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    with pytest.raises(ValueError, match="Member not found in this gym"):
        await svc.ensure_profiles(uuid4(), wrong_gym_id)

    client.embed.assert_not_called()
    assert len(session.executed) == 2


async def test_ensure_profiles_raises_when_member_row_missing() -> None:
    """The member doesn't exist at all: the source query returns no row."""
    pool, _ = _make_pool([_FakeResult(rows=[]), _FakeResult(one=None)])
    client = MagicMock()
    client.embed = AsyncMock()
    svc = MemberVideoProfileService(
        db_pool=pool,
        litellm_client=client,
        embedding_model="test/model",
        embedding_dim=4,
        profile_ttl_days=30,
    )

    with pytest.raises(ValueError, match="Member not found in this gym"):
        await svc.ensure_profiles(uuid4(), uuid4())

    client.embed.assert_not_called()


# ── get_recs: per-bucket queries + record flag ───────────────────────


def _candidate_row(video_id: str = "vid1", score: float = 0.9) -> dict:
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
        "already_recommended": False,
        "similarity": 0.8,
        "score": score,
    }


def _recs_service(pool: MagicMock, profile: AsyncMock) -> VideoRecsService:
    return VideoRecsService(
        db_pool=pool,
        profile_service=profile,
        weight_similarity=0.7,
        weight_relevance=0.2,
        weight_views=0.1,
    )


def _profile_stub() -> AsyncMock:
    profile = AsyncMock()
    profile.ensure_profiles = AsyncMock()
    profile.load_embeddings = AsyncMock(
        return_value={b: "[0.1]" for b in MoodBucket}
    )
    return profile


async def test_get_recs_runs_one_query_per_bucket_no_record() -> None:
    pool, session = _make_pool(
        [_FakeResult(rows=[_candidate_row(f"vid{i}")]) for i in range(5)]
    )
    profile = _profile_stub()
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    profile.ensure_profiles.assert_awaited_once()
    profile.load_embeddings.assert_awaited_once()
    # One candidate query per bucket, and NO record upsert (record=False).
    assert len(session.executed) == 5
    assert len(resp.buckets) == len(MoodBucket)
    assert all(len(b.videos) == 1 for b in resp.buckets)
    assert resp.buckets[0].videos[0].score == pytest.approx(0.9)


async def test_get_recs_records_served_when_record_true() -> None:
    pool, session = _make_pool(
        [_FakeResult(rows=[_candidate_row(f"vid{i}")]) for i in range(5)]
        + [_FakeResult()]  # the record upsert
    )
    profile = _profile_stub()
    svc = _recs_service(pool, profile)

    await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=True)

    # 5 candidate queries + 1 record upsert.
    assert len(session.executed) == 6
    upsert_params = session.executed[5][1]
    assert isinstance(upsert_params, list) and len(upsert_params) == 5
    assert {p["video_id"] for p in upsert_params} == {f"vid{i}" for i in range(5)}


async def test_get_recs_skips_bucket_with_no_profile_embedding() -> None:
    # Only 4 buckets have embeddings → the missing bucket runs no query.
    profile = AsyncMock()
    profile.ensure_profiles = AsyncMock()
    embeddings = {b: "[0.1]" for b in MoodBucket}
    del embeddings[MoodBucket.peak]
    profile.load_embeddings = AsyncMock(return_value=embeddings)
    pool, session = _make_pool(
        [_FakeResult(rows=[_candidate_row()]) for _ in range(4)]
    )
    svc = _recs_service(pool, profile)

    resp = await svc.get_recs(uuid4(), uuid4(), per_bucket=5, record=False)

    assert len(session.executed) == 4  # peak skipped
    peak = next(b for b in resp.buckets if b.bucket is MoodBucket.peak)
    assert peak.videos == []


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
