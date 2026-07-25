"""Live-DB integration for the video RAG read surface (single rec + click).

Drives the real endpoints against the shared local Supabase over ASGI. ``auth``
is always-pass except in the 403 test, which wires the REAL
``verify_gym_employee_for_member`` behind a fake JWT payload. The LLM client is
a deterministic stub: a fixed embedding sized to ``settings.video_embedding_dim``
(the seeded ``video_rag`` row carries the same vector, so retrieval is exact)
and a canned taste summary — no provider calls.

**Every test that seeds videos runs against ``rag_gym``, its OWN throwaway
gym.** The feed/rec reads rank a candidate set scoped to ONE gym, so "my seeded
video is the pick" only asserts anything when the gym's feed holds nothing
else; the shared seeded gym's feed is a live, growing pool spanning every
rotation genre, which would make the precondition seed luck. The two tests that
seed NO videos stay on the seeded ``gym_id``, where their ``members`` /
``gym_employees`` setup lives.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.core.config import settings
from src.main import app
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool

_AUTH_HEADERS = {"Authorization": "Bearer fake-jwt"}
# Read from settings so the test vector tracks the vector(N) column width.
_EMBEDDING_DIM = settings.video_embedding_dim
# One shared vector for the member profile AND the seeded video_rag row, so
# cosine distance is 0 and retrieval is deterministic without a provider call.
_VEC = [0.02] * _EMBEDDING_DIM
_VEC_LITERAL = "[" + ",".join(str(x) for x in _VEC) + "]"


def _vec(nonzero: dict[int, float]) -> str:
    """A pgvector text literal with the given sparse non-zero components."""
    arr = [0.0] * _EMBEDDING_DIM
    for i, v in nonzero.items():
        arr[i] = v
    return "[" + ",".join(str(x) for x in arr) + "]"


# Crafted for the ranking tests — cosine distance (`<=>`) to _MEMBER_VEC is 0.0
# / ~0.0012 / 1.0. A tight #1↔#2 gap with a fat spread (the far cluster) is what
# lets 0.1σ (~0.06) exceed the gap, so the owner boost / served penalty can flip
# the top two. Retuning these numbers breaks both flip tests.
_MEMBER_VEC = _vec({0: 1.0})
_VEC_NEAR = _vec({0: 1.0})
_VEC_NEAR2 = _vec({0: 1.0, 1: 0.05})
_VEC_FAR = _vec({1: 1.0})


class _StubLiteLLM:
    """A LiteLLMClient stand-in: embed returns the fixed vector per input, and
    complete_structured returns a canned taste summary (no chat model call)."""

    async def embed(self, *, texts: list[str], model: str) -> list[list[float]]:
        return [list(_VEC) for _ in texts]

    async def complete_structured(self, *, prompt: str, schema, model: str):
        return schema(summary="a test taste profile")


async def _insert_member(db_pool: DirectDatabasePool, gym_id: UUID) -> UUID:
    """Insert a bare engagement-only member (no Stripe) and return its id."""
    async with db_pool.session() as session, session.begin():
        row = (
            (
                await session.execute(
                    text(
                        "INSERT INTO members (gym_id, first_name, last_name) "
                        "VALUES (:g, 'Rag', 'Tester') RETURNING member_id"
                    ),
                    {"g": str(gym_id)},
                )
            )
            .mappings()
            .fetchone()
        )
    return UUID(str(row["member_id"]))


async def _seed_served_rag_video(
    db_pool: DirectDatabasePool, gym_id: UUID, video_id: str
) -> None:
    """Seed one served, enriched owner video: a pool row (educational genre),
    its video_rag summary embedding, and an accepted run-independent feed row."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text(
                "INSERT INTO video (video_id, url, title, thumbnail_url, "
                "channel_name, channel_url, relevance_index, tag, gym_id, "
                "added_via) VALUES (:vid, :url, 'RAG Vid', :thumb, 'Chan', "
                ":churl, 0, 'educational', :g, 'manual')"
            ),
            {
                "vid": video_id,
                "url": f"https://youtu.be/{video_id}",
                "thumb": "https://img/x.jpg",
                "churl": "https://c",
                "g": str(gym_id),
            },
        )
        await session.execute(
            text(
                "INSERT INTO video_rag (video_id, summary, embedding, "
                "embedding_model) VALUES (:vid, 'a test video', "
                "CAST(:emb AS vector), 'test/model')"
            ),
            {"vid": video_id, "emb": _VEC_LITERAL},
        )
        await session.execute(
            text(
                "INSERT INTO gym_video_feed (gym_id, video_id, video_run_id, "
                "scan_status) VALUES (:g, :vid, NULL, 'accepted')"
            ),
            {"g": str(gym_id), "vid": video_id},
        )


async def _delete_rag_seed(
    db_pool: DirectDatabasePool, member_id: UUID, video_id: str
) -> None:
    """Delete the video (cascades feed + video_rag) and the member (which
    carries the video_profile_* columns and cascades member_video_recs +
    member_activities)."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text("DELETE FROM video WHERE video_id = :vid"), {"vid": video_id}
        )
        await session.execute(
            text("DELETE FROM members WHERE member_id = :m"),
            {"m": str(member_id)},
        )


@pytest.fixture
async def rag_gym(db_pool: DirectDatabasePool) -> AsyncGenerator[UUID]:
    """A throwaway gym whose video feed starts EMPTY — the candidate set the
    seeding tests own outright. Function-scoped, so each test starts clean.

    Created by direct INSERT rather than ``POST /api/v1/gyms/`` on purpose: the
    API path provisions a Stripe Connect account and nothing here bills.

    Teardown is FK-safe and touches only THIS gym, never the seeded gym or the
    shared video pool: ``member_activities`` (no cascade from ``members``) →
    this gym's videos (cascading ``video_rag`` / ``gym_video_feed`` /
    ``member_video_recs``) → ``members`` (no cascade from ``gyms``) → the gym.
    """
    async with db_pool.session() as session, session.begin():
        row = (
            (
                await session.execute(
                    text(
                        "INSERT INTO gyms (gym_name) VALUES (:name) "
                        "RETURNING gym_id"
                    ),
                    {"name": f"ZZ RAG Test Gym {uuid4().hex[:8]}"},
                )
            )
            .mappings()
            .fetchone()
        )
    gym = UUID(str(row["gym_id"]))
    try:
        yield gym
    finally:
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text(
                    "DELETE FROM member_activities WHERE member_id IN "
                    "(SELECT member_id FROM members WHERE gym_id = :g)"
                ),
                {"g": str(gym)},
            )
            await session.execute(
                text("DELETE FROM video WHERE gym_id = :g"), {"g": str(gym)}
            )
            await session.execute(
                text("DELETE FROM members WHERE gym_id = :g"), {"g": str(gym)}
            )
            await session.execute(
                text("DELETE FROM gyms WHERE gym_id = :g"), {"g": str(gym)}
            )


@pytest.fixture
async def rag_client() -> AsyncGenerator[AsyncClient]:
    """ASGI client with auth always-pass, the REAL db_pool, and the LLM client
    stubbed. Resets the profile singleton so it rebuilds against the stub."""
    container = app.container
    auth = _always_pass_auth()
    container.auth.override(auth)
    container.litellm_client.override(_StubLiteLLM())
    container.member_video_profile_service.reset()
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            yield client
    finally:
        container.auth.reset_override()
        container.litellm_client.reset_override()
        container.member_video_profile_service.reset()


def _always_pass_auth() -> MagicMock:
    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": str(uuid4()),
        "email": "test@example.com",
    }
    auth.verify_gym_admin_or_owner = AsyncMock(return_value=None)
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    return auth


async def test_rec_returns_served_video_and_records(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """The GET serves ONE rotating-category rec and records it, appending to the
    append-only ``member_video_recs`` log (0 → 1 → 2; the count is derived, not
    a stored counter). Needs ``rag_gym``: the second serve's rotation index
    advances off ``educational`` and only wraps back when no OTHER genre has a
    candidate."""
    member_id = await _insert_member(db_pool, rag_gym)
    video_id = "ragvid_0001"
    await _seed_served_rag_video(db_pool, rag_gym, video_id)
    base = f"/api/v1/gyms/{rag_gym}/members/{member_id}/video-rec"
    try:
        # First serve: the rotation starts at the seeded video's genre.
        resp = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert resp.status_code == 200
        body = resp.json()
        assert body["category"] == "educational"
        assert video_id in body["video"]["url"]
        assert body["rec_id"]
        assert await _rec_count(db_pool, member_id, video_id) == 1

        # Second serve: no other genre has a candidate, so it wraps back.
        resp2 = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert resp2.status_code == 200
        assert video_id in resp2.json()["video"]["url"]
        assert await _rec_count(db_pool, member_id, video_id) == 2
    finally:
        await _delete_rag_seed(db_pool, member_id, video_id)


async def test_rec_click_stamps_and_logs(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """A click stamps ``clicked_at``, logs a ``video_clicked`` activity and
    returns ``clicked=true``; a repeat is idempotent. Needs ``rag_gym`` so the
    seeded video is the ONLY thing the rec can serve — the assertions name it."""
    member_id = await _insert_member(db_pool, rag_gym)
    video_id = "ragvid_0003"
    await _seed_served_rag_video(db_pool, rag_gym, video_id)
    base = f"/api/v1/gyms/{rag_gym}/members/{member_id}/video-rec"
    try:
        served = await rag_client.get(base, headers=_AUTH_HEADERS)
        rec_id = served.json()["rec_id"]
        assert rec_id is not None

        resp = await rag_client.post(
            f"{base}/{rec_id}/click", headers=_AUTH_HEADERS
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["clicked"] is True
        assert body["video_id"] == video_id
        assert await _clicked_at_set(db_pool, rec_id) is True
        assert await _video_click_activity_count(db_pool, member_id) == 1

        # No re-stamp, no second activity.
        repeat = await rag_client.post(
            f"{base}/{rec_id}/click", headers=_AUTH_HEADERS
        )
        assert repeat.status_code == 200
        assert repeat.json()["clicked"] is False
        assert await _video_click_activity_count(db_pool, member_id) == 1
    finally:
        # member_activities has no cascade FK — clear it before the member.
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text("DELETE FROM member_activities WHERE member_id = :m"),
                {"m": str(member_id)},
            )
        await _delete_rag_seed(db_pool, member_id, video_id)


async def test_rec_wrong_gym_returns_404(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """A caller authorized for the member (auth always-passes here) but asking
    about a DIFFERENT gym gets 404: the path gym_id is verified against the
    member's real gym, never trusted."""
    member_id = await _insert_member(db_pool, gym_id)
    wrong_gym_id = uuid4()
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{wrong_gym_id}/members/{member_id}/video-rec",
            headers=_AUTH_HEADERS,
        )
        assert resp.status_code == 404
    finally:
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text("DELETE FROM members WHERE member_id = :m"),
                {"m": str(member_id)},
            )


async def test_rec_forbidden_for_non_viewer(
    db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """A caller who is not an owner/admin of the member's gym gets 403, through
    the REAL ``verify_gym_employee_for_member`` behind a fake JWT payload."""
    container = app.container
    member_id = await _insert_member(db_pool, gym_id)
    real_auth = Auth(container.db_pool())

    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": str(uuid4()),  # neither the member nor a staff principal
        "email": "outsider@example.com",
    }
    auth.verify_gym_employee_for_member = (
        real_auth.verify_gym_employee_for_member
    )
    container.auth.override(auth)
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            resp = await client.get(
                f"/api/v1/gyms/{gym_id}/members/{member_id}/video-rec",
                headers=_AUTH_HEADERS,
            )
        assert resp.status_code == 403
    finally:
        container.auth.reset_override()
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text("DELETE FROM members WHERE member_id = :m"),
                {"m": str(member_id)},
            )


# ── feed-behavior seeding helpers ─────────────────────────────────────


async def _seed_owner_video(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    video_id: str,
    *,
    tag: str = "educational",
    relevance: int = 0,
    enriched: bool = True,
    scan_status: str = "accepted",
    embedding: str = _VEC_LITERAL,
) -> None:
    """Seed one owner-section (video_run_id NULL) feed video: a pool row, an
    optional video_rag row (enrichment gate), and the feed membership."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text(
                "INSERT INTO video (video_id, url, title, thumbnail_url, "
                "channel_name, channel_url, relevance_index, tag, gym_id, "
                "added_via) VALUES (:vid, :url, 'Vid', :thumb, 'Chan', :churl, "
                ":rel, CAST(:tag AS video_genre), :g, 'manual')"
            ),
            {
                "vid": video_id,
                "url": f"https://youtu.be/{video_id}",
                "thumb": "https://img/x.jpg",
                "churl": "https://c",
                "rel": relevance,
                "tag": tag,
                "g": str(gym_id),
            },
        )
        if enriched:
            await session.execute(
                text(
                    "INSERT INTO video_rag (video_id, summary, embedding, "
                    "embedding_model) VALUES (:vid, 'sum', CAST(:emb AS vector), "
                    "'test/model')"
                ),
                {"vid": video_id, "emb": embedding},
            )
        await session.execute(
            text(
                "INSERT INTO gym_video_feed (gym_id, video_id, video_run_id, "
                "scan_status, curated_at) VALUES (:g, :vid, NULL, "
                "CAST(:st AS gym_video_scan_status), now())"
            ),
            {"g": str(gym_id), "vid": video_id, "st": scan_status},
        )


async def _set_member_embedding(
    db_pool: DirectDatabasePool, member_id: UUID, vec_literal: str
) -> None:
    """Seed the member's taste embedding directly, bypassing the LLM build."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text(
                "UPDATE members SET video_profile_embedding = CAST(:v AS vector), "
                "video_profile_embedding_model = 'test/model', "
                "video_profile_built_at = now() WHERE member_id = :m"
            ),
            {"v": vec_literal, "m": str(member_id)},
        )


async def _record_served(
    db_pool: DirectDatabasePool,
    member_id: UUID,
    gym_id: UUID,
    video_id: str,
    *,
    category: str = "educational",
) -> None:
    """Append a fresh (recommended_at = now()) served-rec row for this member."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text(
                "INSERT INTO member_video_recs (member_id, gym_id, video_id, "
                "category) VALUES (:m, :g, :v, CAST(:c AS video_genre))"
            ),
            {
                "m": str(member_id),
                "g": str(gym_id),
                "v": video_id,
                "c": category,
            },
        )


async def _delete_videos(
    db_pool: DirectDatabasePool, video_ids: list[str]
) -> None:
    """Delete pool videos (cascades their feed + video_rag + rec rows)."""
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text("DELETE FROM video WHERE video_id = ANY(:ids)"),
            {"ids": video_ids},
        )


async def _delete_member_and_videos(
    db_pool: DirectDatabasePool, member_id: UUID, video_ids: list[str]
) -> None:
    """Delete the videos (cascade) and the member (cascades its rec rows)."""
    await _delete_videos(db_pool, video_ids)
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text("DELETE FROM members WHERE member_id = :m"),
            {"m": str(member_id)},
        )


# ── feed serve-path behavior (no member profile needed) ───────────────


async def test_feed_serves_only_enriched(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """The served feed shows an enriched owner video and HIDES an
    accepted-but-un-enriched one (the INNER JOIN on ``video_rag``). Needs
    ``rag_gym`` so the page is exactly these two rows — otherwise the presence
    half depends on ``enr`` landing inside the first ``limit`` ranked rows."""
    enr, bare = "feedenr01", "feedbare01"
    await _seed_owner_video(db_pool, rag_gym, enr, enriched=True)
    await _seed_owner_video(db_pool, rag_gym, bare, enriched=False)
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{rag_gym}/videos?video_type=educational&limit=100",
            headers=_AUTH_HEADERS,
        )
        assert resp.status_code == 200
        cards = {v["video_id"]: v for v in resp.json()["videos"]}
        assert enr in cards
        assert bare not in cards
        assert cards[enr]["owner_added"] is True
        assert cards[enr]["enriched"] is True
    finally:
        await _delete_videos(db_pool, [enr, bare])


async def test_owner_listing_shows_unenriched(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """The ungated owner listing shows an owner video BEFORE enrichment, flagged
    ``enriched=false`` (LEFT JOIN video_rag) — the opposite of the served feed."""
    bare = "ownerbare01"
    await _seed_owner_video(db_pool, rag_gym, bare, enriched=False)
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{rag_gym}/videos/owner?limit=100",
            headers=_AUTH_HEADERS,
        )
        assert resp.status_code == 200
        rows = {v["video_id"]: v for v in resp.json()["videos"]}
        assert bare in rows
        assert rows[bare]["enriched"] is False
        assert rows[bare]["owner_added"] is True
    finally:
        await _delete_videos(db_pool, [bare])


async def test_pending_invisible_in_all_lists(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """A 'pending' row is invisible in the accepted feed, the rejected feed AND
    the owner listing."""
    pend = "pending01"
    await _seed_owner_video(
        db_pool, rag_gym, pend, enriched=True, scan_status="pending"
    )
    try:
        acc = await rag_client.get(
            f"/api/v1/gyms/{rag_gym}/videos?limit=100", headers=_AUTH_HEADERS
        )
        rej = await rag_client.get(
            f"/api/v1/gyms/{rag_gym}/videos?rejected=true&limit=100",
            headers=_AUTH_HEADERS,
        )
        own = await rag_client.get(
            f"/api/v1/gyms/{rag_gym}/videos/owner?limit=100",
            headers=_AUTH_HEADERS,
        )
        assert pend not in [v["video_id"] for v in acc.json()["videos"]]
        assert pend not in [v["video_id"] for v in rej.json()["videos"]]
        assert pend not in [v["video_id"] for v in own.json()["videos"]]
    finally:
        await _delete_videos(db_pool, [pend])


# ── personalized ranking (needs members.video_profile_*) ──────────────


async def test_personalized_served_penalty_flips_top_pick(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """A leads B on cosine until A is served once, after which the decayed
    served penalty (~0.1σ) exceeds the tiny A↔B gap and B takes the top spot.
    The three far videos are there to inflate σ. Needs ``rag_gym``: σ is a
    window over the WHOLE candidate set, so these five videos must BE it."""
    member_id = await _insert_member(db_pool, rag_gym)
    a, b = "flipa01", "flipb01"
    far = ["flipf01", "flipf02", "flipf03"]
    url = (
        f"/api/v1/gyms/{rag_gym}/videos"
        f"?video_type=educational&member_id={member_id}&limit=100"
    )
    try:
        # Seed inside the try so a setup failure still triggers cleanup.
        await _seed_owner_video(
            db_pool, rag_gym, a, embedding=_VEC_NEAR, relevance=0
        )
        await _seed_owner_video(
            db_pool, rag_gym, b, embedding=_VEC_NEAR2, relevance=1
        )
        for i, f in enumerate(far):
            await _seed_owner_video(
                db_pool, rag_gym, f, embedding=_VEC_FAR, relevance=10 + i
            )
        await _set_member_embedding(db_pool, member_id, _MEMBER_VEC)

        before = await rag_client.get(url, headers=_AUTH_HEADERS)
        ids_before = [v["video_id"] for v in before.json()["videos"]]
        assert ids_before[0] == a  # closest by cosine wins pre-penalty

        await _record_served(db_pool, member_id, rag_gym, a)

        after = await rag_client.get(url, headers=_AUTH_HEADERS)
        ids_after = [v["video_id"] for v in after.json()["videos"]]
        assert ids_after[0] == b  # A pushed back by the fresh served penalty
        assert ids_after.index(b) < ids_after.index(a)
    finally:
        await _delete_member_and_videos(db_pool, member_id, [a, b, *far])


async def test_rec_advances_across_consecutive_calls(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, rag_gym: UUID
) -> None:
    """Two consecutive rec GETs return DIFFERENT videos, purely from the decayed
    served penalty the first serve records — there is NO already-served
    anti-join. Needs ``rag_gym`` twice over: the second GET's rotation index
    advances off ``educational`` and only falls back when no other genre has a
    candidate, and σ is a window over the whole candidate set."""
    member_id = await _insert_member(db_pool, rag_gym)
    a, b = "adva01", "advb01"
    far = ["advf01", "advf02", "advf03"]
    base = f"/api/v1/gyms/{rag_gym}/members/{member_id}/video-rec"
    try:
        # Seed inside the try so a setup failure still triggers cleanup.
        await _seed_owner_video(
            db_pool, rag_gym, a, embedding=_VEC_NEAR, relevance=0
        )
        await _seed_owner_video(
            db_pool, rag_gym, b, embedding=_VEC_NEAR2, relevance=1
        )
        for i, f in enumerate(far):
            await _seed_owner_video(
                db_pool, rag_gym, f, embedding=_VEC_FAR, relevance=10 + i
            )
        await _set_member_embedding(db_pool, member_id, _MEMBER_VEC)

        first = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert first.status_code == 200
        assert first.json()["video"]["video_id"] == a

        second = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert second.status_code == 200
        assert second.json()["video"]["video_id"] == b
    finally:
        await _delete_member_and_videos(db_pool, member_id, [a, b, *far])


async def _rec_count(
    db_pool: DirectDatabasePool, member_id: UUID, video_id: str
) -> int:
    """How many times (member, video) has been served — COUNT of log rows."""
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(
                        "SELECT COUNT(*) AS n FROM member_video_recs "
                        "WHERE member_id = :m AND video_id = :v"
                    ),
                    {"m": str(member_id), "v": video_id},
                )
            )
            .mappings()
            .fetchone()
        )
    return int(row["n"])


async def _clicked_at_set(db_pool: DirectDatabasePool, rec_id: UUID) -> bool:
    """True when the rec's ``clicked_at`` has been stamped."""
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(
                        "SELECT clicked_at FROM member_video_recs "
                        "WHERE rec_id = :r"
                    ),
                    {"r": str(rec_id)},
                )
            )
            .mappings()
            .fetchone()
        )
    return row is not None and row["clicked_at"] is not None


async def _video_click_activity_count(
    db_pool: DirectDatabasePool, member_id: UUID
) -> int:
    """How many ``video_clicked`` activities the member has logged."""
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(
                        "SELECT COUNT(*) AS n FROM member_activities "
                        "WHERE member_id = :m AND activity_type = 'video_clicked'"
                    ),
                    {"m": str(member_id)},
                )
            )
            .mappings()
            .fetchone()
        )
    return int(row["n"])
