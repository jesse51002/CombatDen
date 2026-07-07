"""Live-DB integration for the video RAG read surface (recs + search).

Drives the real endpoints against the shared local Supabase over an ASGI
transport. ``auth`` is overridden always-pass for the happy-path tests; the
403 test wires the REAL ``verify_can_view_member`` behind a fake JWT payload so
a non-viewer is rejected. The embedding provider is overridden with a
deterministic 1536-dim stub so no OpenAI call is made — the seeded
``video_rag`` row carries the same vector so it retrieves cleanly.

Requires migration ``20260703000001_video_worker_rag`` (pgvector + the
``video_rag`` / ``member_video_profile`` / ``member_video_recs`` tables). When
the shared local DB has NOT had that migration applied, the recs/search tests
fail at the query — the expected "pending migration apply" state, not a code
fault. The 403 test only reads ``members`` / ``gym_employees`` and passes
regardless.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.main import app
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool

_AUTH_HEADERS = {"Authorization": "Bearer fake-jwt"}
_EMBEDDING_DIM = 1536
# One shared deterministic vector: the member profile embeddings AND the seeded
# video_rag row use it, so cosine distance is 0 (similarity 1) and retrieval is
# deterministic without an OpenAI call.
_VEC = [0.02] * _EMBEDDING_DIM
_VEC_LITERAL = "[" + ",".join(str(x) for x in _VEC) + "]"


class _StubLiteLLM:
    """A LiteLLMClient stand-in: embed returns the fixed vector per input."""

    async def embed(self, *, texts: list[str], model: str) -> list[list[float]]:
        return [list(_VEC) for _ in texts]


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
    """Seed one served, enriched owner video: a pool row (educational → teach),
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
    """Delete the video (cascades feed + video_rag) and the member (cascades
    member_video_profile + member_video_recs)."""
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
    auth.verify_gym_employee = AsyncMock(return_value=None)
    auth.verify_can_view_member = AsyncMock(return_value=None)
    return auth


async def test_recs_returns_served_video_and_records(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """recs=false → the seeded video appears in its bucket, nothing recorded;
    recs=true → a new member_video_recs row is appended per serve (the log
    grows 0 → 1 → 2; count is derived, not a stored counter)."""
    member_id = await _insert_member(db_pool, gym_id)
    video_id = "ragvid_0001"
    await _seed_served_rag_video(db_pool, gym_id, video_id)
    base = f"/api/v1/gyms/{gym_id}/members/{member_id}/video-recs"
    try:
        # Preview (record=false): shape + no history write.
        resp = await rag_client.get(f"{base}?record=false", headers=_AUTH_HEADERS)
        assert resp.status_code == 200
        buckets = {b["bucket"]: b for b in resp.json()["buckets"]}
        assert set(buckets) == {"teach", "enjoy", "inform", "human", "peak"}
        teach_ids = [v["url"] for v in buckets["teach"]["videos"]]
        assert any(video_id in u for u in teach_ids)
        assert await _rec_count(db_pool, member_id, video_id) == 0

        # Record twice: the append-only log grows 1 → 2 rows for this video.
        await rag_client.get(f"{base}?record=true", headers=_AUTH_HEADERS)
        assert await _rec_count(db_pool, member_id, video_id) == 1
        await rag_client.get(f"{base}?record=true", headers=_AUTH_HEADERS)
        assert await _rec_count(db_pool, member_id, video_id) == 2
    finally:
        await _delete_rag_seed(db_pool, member_id, video_id)


async def test_recs_wrong_gym_returns_404(
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
            f"/api/v1/gyms/{wrong_gym_id}/members/{member_id}/video-recs",
            headers=_AUTH_HEADERS,
        )
        assert resp.status_code == 404
    finally:
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text("DELETE FROM members WHERE member_id = :m"),
                {"m": str(member_id)},
            )


async def test_search_returns_served_video(
    rag_client: AsyncClient, db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """search returns 200 and the seeded served video with a similarity score."""
    member_id = await _insert_member(db_pool, gym_id)
    video_id = "ragvid_0002"
    await _seed_served_rag_video(db_pool, gym_id, video_id)
    try:
        resp = await rag_client.get(
            f"/api/v1/gyms/{gym_id}/videos/search?q=test video&limit=10",
            headers=_AUTH_HEADERS,
        )
        assert resp.status_code == 200
        results = resp.json()["results"]
        assert any(video_id in r["url"] for r in results)
        assert all("similarity" in r for r in results)
    finally:
        await _delete_rag_seed(db_pool, member_id, video_id)


async def test_recs_forbidden_for_non_viewer(
    db_pool: DirectDatabasePool, gym_id: UUID
) -> None:
    """A caller who is neither the member nor gym staff gets 403 (real
    verify_can_view_member behind a fake JWT payload). Touches only members /
    gym_employees, so it passes regardless of the RAG migration state."""
    container = app.container
    member_id = await _insert_member(db_pool, gym_id)
    real_auth = Auth(container.supabase())

    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": str(uuid4()),  # neither the member nor a staff principal
        "email": "outsider@example.com",
    }
    auth.verify_can_view_member = real_auth.verify_can_view_member
    container.auth.override(auth)
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            resp = await client.get(
                f"/api/v1/gyms/{gym_id}/members/{member_id}/video-recs",
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
