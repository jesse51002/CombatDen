"""Pure-logic unit tests for the video RAG read surface (no DB / no OpenAI).

Covers the services driven against a fake DB pool + fake litellm client:
``verify_member_in_gym`` (the READ-ONLY ownership guard — passes / raises,
NEVER builds), ``refresh_if_due`` (cooldown no-op vs stale rebuild + the
embedding-dimension guard), ``load_embedding``, the rotating single-rec
``get_rec`` (rotation index by served count, empty-category fall-through,
forwards the member_id to the feed, records + returns rec_id with the video as a
``GymVideoCard``, None when nothing available, propagates the ownership error —
the rec is now a thin wrapper over a faked ``VideoFeedService.load_feed_page``),
and the unified feed page (``VideoFeedService.load_feed_page`` always binds the
member_embedding — text or NULL — plus the member_id / rank knobs, and reads the
embedding only when a member_id is supplied).
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.video import VideoGenre

from src.videos.schema.member_profile_schema import MemberProfileSummary
from src.videos.schema.video_recs_schema import MemberVideoRec
from src.videos.schema.videos_schema import GymVideoCard
from src.videos.service.member_video_profile_service import (
    MemberNotInGymError,
    MemberVideoProfileService,
)
from src.videos.service.video_feed_service import VideoFeedService
from src.videos.service.video_recs_service import VideoRecsService

# Feed-ranking knobs the VideoFeedService under test is built with.
_BUMP_FRACTION = 0.10
_HALF_LIFE_DAYS = 7.0

# ── fake DB pool ─────────────────────────────────────────────────────


class _FakeResult:
    """A stand-in for a SQLAlchemy result: ``.mappings().all()/.fetchone()``."""

    def __init__(self, rows: list[dict] | None = None, one: dict | None = None):
        self._rows = rows if rows is not None else []
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


# ── verify_member_in_gym: read-only guard, never builds ──────────────


async def test_verify_member_in_gym_passes_and_never_builds() -> None:
    gym_id = uuid4()
    # Even with NO embedding, verify must NOT build — a read has no side effect.
    pool, session = _make_pool([_load_result(gym_id, embedding=None)])
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.verify_member_in_gym(uuid4(), gym_id)

    client.complete_structured.assert_not_called()
    client.embed.assert_not_called()
    assert len(session.executed) == 1  # only the load ran, no build


async def test_verify_member_in_gym_raises_on_gym_mismatch() -> None:
    real_gym_id = uuid4()
    wrong_gym_id = uuid4()
    pool, session = _make_pool([_load_result(real_gym_id, embedding=None)])
    svc = _profile_service(pool, _summary_client())

    with pytest.raises(MemberNotInGymError, match="Member not found in this gym"):
        await svc.verify_member_in_gym(uuid4(), wrong_gym_id)
    assert len(session.executed) == 1


async def test_verify_member_in_gym_raises_when_member_missing() -> None:
    pool, session = _make_pool([_load_result(None)])
    svc = _profile_service(pool, _summary_client())

    with pytest.raises(MemberNotInGymError, match="Member not found in this gym"):
        await svc.verify_member_in_gym(uuid4(), uuid4())
    assert len(session.executed) == 1


# ── refresh_if_due: cooldown no-op vs stale rebuild + dim guard ──────


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


async def test_refresh_if_due_rebuilds_when_embedding_missing() -> None:
    gym_id = uuid4()
    pool, session = _make_pool(
        [
            _load_result(gym_id, embedding=None),  # no embedding → rebuild
            _source_result(gym_id),
            _FakeResult(),
        ]
    )
    client = _summary_client()
    svc = _profile_service(pool, client)

    await svc.refresh_if_due(uuid4(), gym_id)

    client.embed.assert_awaited_once()
    assert len(session.executed) == 3
    assert session.executed[2][1]["embedding"] == "[0.1,0.1,0.1,0.1]"


async def test_refresh_if_due_raises_on_embedding_dim_mismatch() -> None:
    gym_id = uuid4()
    pool, _ = _make_pool(
        [_load_result(gym_id, embedding=None), _source_result(gym_id)]
    )
    client = _summary_client(dim=2)  # embed returns dim 2, service expects 4
    svc = _profile_service(pool, client)

    with pytest.raises(ValueError, match="embedding dimension"):
        await svc.refresh_if_due(uuid4(), gym_id)


# ── load_embedding ───────────────────────────────────────────────────


async def test_load_embedding_returns_text_when_built() -> None:
    gym_id = uuid4()
    pool, _ = _make_pool([_load_result(gym_id, embedding="[0.3,0.4]")])
    svc = _profile_service(pool, _summary_client())

    assert await svc.load_embedding(uuid4()) == "[0.3,0.4]"


async def test_load_embedding_returns_none_when_absent() -> None:
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


# ── get_rec: rotating single-category recommendation ─────────────────

# A fixed 3-genre rotation makes the served-count index deterministic.
_ROTATION = [
    VideoGenre.educational,
    VideoGenre.professional,
    VideoGenre.analysis,
]


def _rec_card(
    video_id: str = "vid1", tag: str = "educational"
) -> GymVideoCard:
    """The single ranked card VideoFeedService.load_feed_page(limit=1) returns."""
    return GymVideoCard(
        video_id=video_id,
        url=f"https://youtu.be/{video_id}",
        title="Test",
        thumbnail_url="https://img/x.jpg",
        channel_name="Chan",
        channel_url="https://c",
        channel_avatar_url="",
        view_count=100,
        duration_seconds=60,
        tag=tag,
        relevance_index=0,
    )


def _count_result(n: int) -> _FakeResult:
    return _FakeResult(one={"n": n})


def _rec_id_result(rec_id: object) -> _FakeResult:
    return _FakeResult(one={"rec_id": str(rec_id)})


class _FakeFeed:
    """A stand-in for VideoFeedService: ``load_feed_page`` returns a one-card
    page (``[card], 1``) for each category present in the mapping (an empty page
    otherwise), and records every call so the rotation + the forwarded member_id
    can be asserted. The rec calls it filtered to one genre with ``limit=1``."""

    def __init__(self, by_category: dict[VideoGenre, GymVideoCard]):
        self._by_category = by_category
        self.calls: list[tuple] = []

    async def load_feed_page(
        self,
        gym_id: object,
        *,
        video_type: VideoGenre,
        member_id: object,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        self.calls.append((gym_id, member_id, video_type, limit, offset))
        card = self._by_category.get(video_type)
        return ([card], 1) if card is not None else ([], 0)


def _recs_service(
    pool: MagicMock, profile: AsyncMock, feed: _FakeFeed
) -> VideoRecsService:
    return VideoRecsService(
        db_pool=pool,
        profile_service=profile,
        feed_service=feed,
        rotation=list(_ROTATION),
    )


def _profile_stub(embedding: str | None = "[0.1]") -> AsyncMock:
    profile = AsyncMock()
    profile.verify_member_in_gym = AsyncMock()
    profile.load_embedding = AsyncMock(return_value=embedding)
    return profile


async def test_get_rec_rotation_index_by_served_count() -> None:
    # served_count = 1 → start = 1 % 3 → the professional category is served.
    rec_id = uuid4()
    member_id = uuid4()
    pool, session = _make_pool([_count_result(1), _rec_id_result(rec_id)])
    profile = _profile_stub(embedding="[0.9]")
    feed = _FakeFeed({VideoGenre.professional: _rec_card("vp", "professional")})
    svc = _recs_service(pool, profile, feed)

    rec = await svc.get_rec(uuid4(), member_id)

    profile.verify_member_in_gym.assert_awaited_once()
    # get_rec no longer loads the embedding itself — load_feed_page does.
    profile.load_embedding.assert_not_called()
    assert isinstance(rec, MemberVideoRec)
    assert rec.category == VideoGenre.professional
    assert rec.rec_id == rec_id
    # Only the professional category was queried (start index 1), member_id passed.
    assert [c[2] for c in feed.calls] == [VideoGenre.professional]
    assert feed.calls[0][1] == member_id
    # DB touched twice only: served-count read + record insert.
    assert len(session.executed) == 2


async def test_get_rec_falls_through_empty_category() -> None:
    # served_count = 0 → start educational, which yields an empty page → advance
    # to professional, which yields the pick.
    rec_id = uuid4()
    pool, session = _make_pool([_count_result(0), _rec_id_result(rec_id)])
    profile = _profile_stub()
    feed = _FakeFeed(
        {VideoGenre.professional: _rec_card("vp", "professional")}
    )
    svc = _recs_service(pool, profile, feed)

    rec = await svc.get_rec(uuid4(), uuid4())

    assert rec is not None
    assert rec.category == VideoGenre.professional
    # educational (empty) → professional (pick); no query past the winner.
    assert [c[2] for c in feed.calls] == [
        VideoGenre.educational,
        VideoGenre.professional,
    ]
    assert len(session.executed) == 2


async def test_get_rec_forwards_member_id_to_feed() -> None:
    # get_rec forwards the member_id + limit=1 to the feed read; the embedding
    # handling (incl. the no-profile relevance fallback) lives inside the feed.
    rec_id = uuid4()
    member_id = uuid4()
    pool, session = _make_pool([_count_result(0), _rec_id_result(rec_id)])
    profile = _profile_stub(embedding=None)
    feed = _FakeFeed(
        {VideoGenre.educational: _rec_card("d0", "educational")}
    )
    svc = _recs_service(pool, profile, feed)

    rec = await svc.get_rec(uuid4(), member_id)

    assert rec is not None
    assert rec.category == VideoGenre.educational
    # (gym_id, member_id, video_type, limit, offset)
    assert feed.calls[0][1] == member_id
    assert feed.calls[0][3] == 1  # limit=1
    assert feed.calls[0][4] == 0  # offset=0


async def test_get_rec_records_pick_and_returns_rec_id() -> None:
    rec_id = uuid4()
    pool, session = _make_pool([_count_result(0), _rec_id_result(rec_id)])
    profile = _profile_stub()
    feed = _FakeFeed(
        {VideoGenre.educational: _rec_card("ve", "educational")}
    )
    svc = _recs_service(pool, profile, feed)

    rec = await svc.get_rec(uuid4(), uuid4())

    assert rec.rec_id == rec_id
    assert rec.video.url.endswith("ve")
    assert isinstance(rec.video, GymVideoCard)
    # The last execute is the record insert — the served pick, and NO score bind.
    insert_params = session.executed[-1][1]
    assert insert_params["video_id"] == "ve"
    assert insert_params["category"] == "educational"
    assert "score" not in insert_params


async def test_get_rec_returns_none_when_no_category_yields() -> None:
    # Every category in the rotation is empty → None (route maps to 404), and
    # nothing is recorded.
    pool, session = _make_pool([_count_result(0)])
    profile = _profile_stub()
    feed = _FakeFeed({})  # no category yields a candidate
    svc = _recs_service(pool, profile, feed)

    rec = await svc.get_rec(uuid4(), uuid4())

    assert rec is None
    # Every rotation category was tried; only the served-count read hit the DB.
    assert len(feed.calls) == len(_ROTATION)
    assert len(session.executed) == 1


async def test_get_rec_propagates_member_not_in_gym() -> None:
    pool, session = _make_pool([])
    profile = AsyncMock()
    profile.verify_member_in_gym = AsyncMock(
        side_effect=MemberNotInGymError("Member not found in this gym")
    )
    profile.load_embedding = AsyncMock()
    feed = _FakeFeed({})
    svc = _recs_service(pool, profile, feed)

    with pytest.raises(MemberNotInGymError):
        await svc.get_rec(uuid4(), uuid4())

    assert len(session.executed) == 0
    assert len(feed.calls) == 0
    profile.load_embedding.assert_not_called()


# ── unified feed page: one SQL, always binds the rank params ─────────


def _feed_row(video_id: str = "fv1") -> dict:
    """A minimal feed-page row with a ``total`` column (validates as a card)."""
    return {
        "video_id": video_id,
        "url": f"https://youtu.be/{video_id}",
        "title": "Feed Vid",
        "thumbnail_url": "https://img/x.jpg",
        "channel_name": "Chan",
        "channel_url": "https://c",
        "channel_avatar_url": "",
        "view_count": 100,
        "duration_seconds": 60,
        "tag": "educational",
        "relevance_index": 0,
        "owner_added": False,
        "total": 1,
    }


def _feed_service(pool: MagicMock, embedding: str | None) -> VideoFeedService:
    profile = AsyncMock()
    profile.load_embedding = AsyncMock(return_value=embedding)
    return VideoFeedService(
        db_pool=pool,
        youtube_client=MagicMock(),
        profile_service=profile,
        bump_sigma_fraction=_BUMP_FRACTION,
        watch_penalty_half_life_days=_HALF_LIFE_DAYS,
    )


async def test_feed_page_binds_embedding_and_member_id_when_profile_built() -> None:
    pool, session = _make_pool([_FakeResult(rows=[_feed_row()])])
    svc = _feed_service(pool, embedding="[0.1,0.2]")
    member_id = uuid4()

    cards, total = await svc.load_feed_page(
        uuid4(), member_id=member_id, limit=10, offset=0
    )

    assert total == 1 and len(cards) == 1
    sql, params = session.executed[0]
    # The one unified SQL always carries the pgvector distance operator.
    assert "<=>" in sql
    assert params["member_embedding"] == "[0.1,0.2]"
    assert params["member_id"] == str(member_id)
    assert params["bump_fraction"] == _BUMP_FRACTION
    assert params["half_life_seconds"] == _HALF_LIFE_DAYS * 86400


async def test_feed_page_binds_null_embedding_when_no_profile() -> None:
    pool, session = _make_pool([_FakeResult(rows=[_feed_row()])])
    svc = _feed_service(pool, embedding=None)  # member has no profile yet
    member_id = uuid4()

    cards, total = await svc.load_feed_page(
        uuid4(), member_id=member_id, limit=10, offset=0
    )

    assert total == 1 and len(cards) == 1
    sql, params = session.executed[0]
    # Same SQL — the embedding is just bound NULL; member_id still bound for the
    # decayed watch penalty subquery.
    assert "<=>" in sql
    assert params["member_embedding"] is None
    assert params["member_id"] == str(member_id)


async def test_feed_page_skips_embedding_read_when_no_member_id() -> None:
    pool, session = _make_pool([_FakeResult(rows=[_feed_row()])])
    profile = AsyncMock()
    profile.load_embedding = AsyncMock(return_value="[0.1]")
    svc = VideoFeedService(
        db_pool=pool,
        youtube_client=MagicMock(),
        profile_service=profile,
        bump_sigma_fraction=_BUMP_FRACTION,
        watch_penalty_half_life_days=_HALF_LIFE_DAYS,
    )

    await svc.load_feed_page(uuid4(), limit=10, offset=0)

    # No member_id → no embedding read; embedding + member_id bound NULL.
    profile.load_embedding.assert_not_called()
    params = session.executed[0][1]
    assert params["member_embedding"] is None
    assert params["member_id"] is None
