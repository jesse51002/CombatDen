"""Live-DB integration for the video-worker control surface.

Drives the real endpoints (``POST /video-worker/run`` + ``GET
/video-worker/status``) against the shared local Supabase via an ASGI transport,
with ``auth`` overridden so the gym-employee gate always passes. Uses the
session-scoped ``db_pool`` + seeded ``gym_id`` fixtures to verify + clean up the
queue row it creates.

Requires migration ``20260703000000_video_worker_rag`` (the ``video_worker_queue``
table + ``video_run.status`` column). When the shared local DB has NOT had that
migration applied, these fail at the query — that is the expected "pending
migration apply" state, not a code fault.
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


@pytest.fixture
async def worker_client() -> AsyncGenerator[AsyncClient]:
    """An async client over the ASGI app with ``auth`` overridden (always-pass)
    but the REAL container ``db_pool`` — so requests hit the live local DB."""
    container = app.container
    auth = MagicMock(spec=Auth)
    auth.get_current_user.return_value = {
        "sub": str(uuid4()),
        "email": "test@example.com",
    }
    auth.verify_gym_employee = AsyncMock(return_value=None)
    container.auth.override(auth)
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            yield client
    finally:
        container.auth.reset_override()


@pytest.fixture
async def cleanup_worker_queue(
    db_pool: DirectDatabasePool, gym_id: UUID
) -> AsyncGenerator[None]:
    """Delete the seeded gym's queue row on teardown (inline text() cleanup)."""
    yield
    async with db_pool.session() as session, session.begin():
        await session.execute(
            text("DELETE FROM video_worker_queue WHERE gym_id = :g"),
            {"g": str(gym_id)},
        )


async def test_run_enqueues_and_status_reflects_queued(
    worker_client: AsyncClient,
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    cleanup_worker_queue: None,
) -> None:
    """POST run → 202 + a real queue row; GET status then reports queued=true."""
    resp = await worker_client.post(
        f"/api/v1/gyms/{gym_id}/video-worker/run", headers=_AUTH_HEADERS
    )
    assert resp.status_code == 202
    assert resp.json() == {"queued": True}

    # The queue row exists, stamped with the manual reason.
    async with db_pool.session() as session:
        row = (
            (
                await session.execute(
                    text(
                        "SELECT reason FROM video_worker_queue "
                        "WHERE gym_id = :g"
                    ),
                    {"g": str(gym_id)},
                )
            )
            .mappings()
            .fetchone()
        )
    assert row is not None
    assert row["reason"] == "manual"

    status_resp = await worker_client.get(
        f"/api/v1/gyms/{gym_id}/video-worker/status", headers=_AUTH_HEADERS
    )
    assert status_resp.status_code == 200
    assert status_resp.json()["queued"] is True


async def test_status_no_runs_returns_none_last_updated(
    worker_client: AsyncClient,
) -> None:
    """A gym with no runs and no queue row → all-empty status."""
    fresh_gym = uuid4()
    resp = await worker_client.get(
        f"/api/v1/gyms/{fresh_gym}/video-worker/status", headers=_AUTH_HEADERS
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["last_updated"] is None
    assert body["queued"] is False
    assert body["running"] is False
    assert body["last_run_status"] is None
