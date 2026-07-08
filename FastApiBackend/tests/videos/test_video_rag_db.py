"""Live-DB integration for the video RAG read surface (single rec + click).

Drives the real endpoints against the shared local Supabase over an ASGI
transport. ``auth`` is overridden always-pass for the happy-path tests; the
403 test wires the REAL ``verify_can_view_member`` behind a fake JWT payload so
a non-viewer is rejected. The LLM client is overridden with a deterministic
stub — its embedding is a fixed 1536-dim vector (no OpenAI call) that the seeded
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
    auth.verify_gym_employee = AsyncMock(return_value=None)
    auth.verify_can_view_member = AsyncMock(return_value=None)
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
