"""Live-DB integration for the video RAG read surface (single rec + click).

Drives the real endpoints against the shared local Supabase over an ASGI
transport. ``auth`` is overridden always-pass for the happy-path tests; the
403 test wires the REAL ``verify_gym_employee_for_member`` behind a fake JWT
payload so a caller who is not staff of the member's gym is rejected. The LLM
client is overridden with a deterministic stub — its embedding is a fixed
vector sized to ``settings.video_embedding_dim`` (no provider call) that the
seeded
``video_rag`` row also carries so retrieval is clean, and its summary call
returns a canned taste paragraph (no chat model call).

The rec surface serves ONE rotating-category recommendation and records it, so a
GET returns ``{rec_id, category, video}`` and appends a ``member_video_recs``
row. The per-member RAG profile is columns on ``members``
(``video_profile_summary`` / ``video_profile_embedding`` / …), not a sidecar
table. These tests require the pending video-worker-RAG migration (pgvector, the
``video_rag`` / ``member_video_recs`` tables, the ``members.video_profile_*``
columns, and ``member_video_recs.clicked_at``). Until it is applied on the
shared local DB, the rec/click tests fail at the query — the expected
"pending migration apply" state, not a code fault. The 403 test only reads
``members`` / ``gym_employees`` and passes regardless.
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
# Sized to the cross-service embedding contract so the test vector always matches
# the vector(N) column width (tracks video_embedding_dim through model changes).
_EMBEDDING_DIM = settings.video_embedding_dim
# One shared deterministic vector: the member profile embeddings AND the seeded
# video_rag row use it, so cosine distance is 0 (similarity 1) and retrieval is
# deterministic without an OpenAI call.
_VEC = [0.02] * _EMBEDDING_DIM
_VEC_LITERAL = "[" + ",".join(str(x) for x in _VEC) + "]"


def _vec(nonzero: dict[int, float]) -> str:
    """A pgvector text literal with the given sparse non-zero components."""
    arr = [0.0] * _EMBEDDING_DIM
    for i, v in nonzero.items():
        arr[i] = v
    return "[" + ",".join(str(x) for x in arr) + "]"


# Crafted vectors for the ranking tests. Cosine distance (`<=>`) to _MEMBER_VEC:
#   _VEC_NEAR  → 0.0     (identical direction)
#   _VEC_NEAR2 → ~0.0012 (a 0.05 nudge on axis 1)
#   _VEC_FAR   → 1.0     (orthogonal)
# A tight #1↔#2 gap (~0.0012) with a fat spread (the far cluster) is what lets
# 0.1σ (~0.06) exceed the gap so the owner boost / served penalty can flip #1↔#2.
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
async def rag_client() -> AsyncGenerator[AsyncClient]:
    """ASGI client with auth always-pass, the REAL db_pool, and the embedding
    provider stubbed (deterministic, no OpenAI). Resets the profile singleton so
    it rebuilds against the stub."""
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
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """The GET serves ONE rotating-category rec and records it: the rotation
    starts at ``educational`` (the seeded video's genre), so the first GET
    returns the seeded video with its rec_id and appends a member_video_recs row
    (the append-only log grows 0 → 1 → 2 as the only-educational video is
    re-served; count is derived, not a stored counter)."""
    member_id = await _insert_member(db_pool, gym_id)
    video_id = "ragvid_0001"
    await _seed_served_rag_video(db_pool, gym_id, video_id)
    base = f"/api/v1/gyms/{gym_id}/members/{member_id}/video-rec"
    try:
        # First serve: rotation start (educational) yields the seeded video and
        # records exactly one row.
        resp = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert resp.status_code == 200
        body = resp.json()
        assert body["category"] == "educational"
        assert video_id in body["video"]["url"]
        assert body["rec_id"]
        assert await _rec_count(db_pool, member_id, video_id) == 1

        # Second serve: only educational has a video, so it is served again and
        # the append-only log grows 1 → 2 rows for this video.
        resp2 = await rag_client.get(base, headers=_AUTH_HEADERS)
        assert resp2.status_code == 200
        assert video_id in resp2.json()["video"]["url"]
        assert await _rec_count(db_pool, member_id, video_id) == 2
    finally:
        await _delete_rag_seed(db_pool, member_id, video_id)


async def test_rec_click_stamps_and_logs(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """Serving a rec then POSTing a click stamps ``clicked_at`` on that rec,
    logs a ``video_clicked`` activity, and returns ``clicked=true``; a repeat
    click is idempotent (``clicked=false``, no second activity)."""
    member_id = await _insert_member(db_pool, gym_id)
    video_id = "ragvid_0003"
    await _seed_served_rag_video(db_pool, gym_id, video_id)
    base = f"/api/v1/gyms/{gym_id}/members/{member_id}/video-rec"
    try:
        # Serve a rec — the GET records it and returns its rec_id to click.
        served = await rag_client.get(base, headers=_AUTH_HEADERS)
        rec_id = served.json()["rec_id"]
        assert rec_id is not None

        # First click: stamped + logged.
        resp = await rag_client.post(
            f"{base}/{rec_id}/click", headers=_AUTH_HEADERS
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["clicked"] is True
        assert body["video_id"] == video_id
        assert await _clicked_at_set(db_pool, rec_id) is True
        assert await _video_click_activity_count(db_pool, member_id) == 1

        # Repeat click: idempotent (no re-stamp, no second activity).
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
    """A caller authorized to view the member (auth always-passes here) but
    asking about a DIFFERENT gym_id than the member's own gym is rejected with
    404 — the security fix: the path gym_id must be verified against the
    member's real gym, not trusted blindly."""
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
    """A caller who is not an owner/admin of the member's gym gets 403 (the
    real verify_gym_employee_for_member behind a fake JWT payload). Touches
    only members / gym_employees / auth.users, so it passes regardless of the
    RAG migration state."""
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
    """Seed the member's taste embedding directly (bypasses the LLM build path).
    Writes members.video_profile_* — fails until the RAG migration is applied."""
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
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """The unified served feed shows an enriched owner video and HIDES an
    accepted-but-un-enriched one (INNER JOIN video_rag). No member_id, so no
    members.video_profile_* read — runs without the members-column migration."""
    enr, bare = "feedenr01", "feedbare01"
    await _seed_owner_video(db_pool, gym_id, enr, enriched=True)
    await _seed_owner_video(db_pool, gym_id, bare, enriched=False)
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos?video_type=educational&limit=100",
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
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """The ungated owner listing shows an owner video BEFORE enrichment, flagged
    ``enriched=false`` (LEFT JOIN video_rag) — the opposite of the served feed."""
    bare = "ownerbare01"
    await _seed_owner_video(db_pool, gym_id, bare, enriched=False)
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos/owner?limit=100",
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
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """A 'pending' scan_status row (worker candidate, enriched or not) is invisible
    in the accepted feed, the rejected feed, AND the owner listing."""
    pend = "pending01"
    await _seed_owner_video(
        db_pool, gym_id, pend, enriched=True, scan_status="pending"
    )
    try:
        acc = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos?limit=100", headers=_AUTH_HEADERS
        )
        rej = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos?rejected=true&limit=100",
            headers=_AUTH_HEADERS,
        )
        own = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos/owner?limit=100",
            headers=_AUTH_HEADERS,
        )
        assert pend not in [v["video_id"] for v in acc.json()["videos"]]
        assert pend not in [v["video_id"] for v in rej.json()["videos"]]
        assert pend not in [v["video_id"] for v in own.json()["videos"]]
    finally:
        await _delete_videos(db_pool, [pend])


# ── personalized ranking (needs members.video_profile_*) ──────────────


async def test_personalized_served_penalty_flips_top_pick(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """With a member embedding bound, A (cosine 0) leads B (cosine ~0.0012). After
    A is served once (a fresh member_video_recs row), the decayed served penalty
    (~0.1σ) exceeds the tiny A↔B gap and B becomes the top pick. Three far videos
    (cosine 1.0) inflate σ. Migration-gated on members.video_profile_*."""
    member_id = await _insert_member(db_pool, gym_id)
    a, b = "flipa01", "flipb01"
    far = ["flipf01", "flipf02", "flipf03"]
    url = (
        f"/api/v1/gyms/{gym_id}/videos"
        f"?video_type=educational&member_id={member_id}&limit=100"
    )
    try:
        # Seed inside the try so a setup failure (e.g. missing video_profile_*
        # before the migration) still triggers cleanup.
        await _seed_owner_video(
            db_pool, gym_id, a, embedding=_VEC_NEAR, relevance=0
        )
        await _seed_owner_video(
            db_pool, gym_id, b, embedding=_VEC_NEAR2, relevance=1
        )
        for i, f in enumerate(far):
            await _seed_owner_video(
                db_pool, gym_id, f, embedding=_VEC_FAR, relevance=10 + i
            )
        await _set_member_embedding(db_pool, member_id, _MEMBER_VEC)

        before = await rag_client.get(url, headers=_AUTH_HEADERS)
        ids_before = [v["video_id"] for v in before.json()["videos"]]
        assert ids_before[0] == a  # closest by cosine wins pre-penalty

        await _record_served(db_pool, member_id, gym_id, a)

        after = await rag_client.get(url, headers=_AUTH_HEADERS)
        ids_after = [v["video_id"] for v in after.json()["videos"]]
        assert ids_after[0] == b  # A pushed back by the fresh served penalty
        assert ids_after.index(b) < ids_after.index(a)
    finally:
        await _delete_member_and_videos(db_pool, member_id, [a, b, *far])


async def test_rec_advances_across_consecutive_calls(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """Two consecutive rec GETs return DIFFERENT videos: the first serves A (the
    closest educational pick), and the decayed served penalty it records pushes A
    below B on the next serve (needed ~5 clustered candidates — 2 near at cosine
    0/0.0012 plus 3 orthogonal at cosine 1.0 to fatten σ — for 0.1σ to clear the
    #1↔#2 gap). No already-served anti-join. Migration-gated on
    members.video_profile_*."""
    member_id = await _insert_member(db_pool, gym_id)
    a, b = "adva01", "advb01"
    far = ["advf01", "advf02", "advf03"]
    base = f"/api/v1/gyms/{gym_id}/members/{member_id}/video-rec"
    try:
        # Seed inside the try so a setup failure (e.g. missing video_profile_*
        # before the migration) still triggers cleanup.
        await _seed_owner_video(
            db_pool, gym_id, a, embedding=_VEC_NEAR, relevance=0
        )
        await _seed_owner_video(
            db_pool, gym_id, b, embedding=_VEC_NEAR2, relevance=1
        )
        for i, f in enumerate(far):
            await _seed_owner_video(
                db_pool, gym_id, f, embedding=_VEC_FAR, relevance=10 + i
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
