"""Live-DB integration for the video-worker STATUS endpoint (read-only).

Drives ``GET /video-worker/status`` against the shared local Supabase via an ASGI
transport, with ``auth`` overridden so the gym-employee gate always passes. There
is no queue and no manual-run endpoint — the worker derives its own work — so this
only exercises the status projection over ``video_run``.

Requires migration ``20260703000000_video_worker_rag`` (the ``video_run.status``
column). When the shared local DB has NOT had that migration applied, these fail
at the query — the expected "pending migration apply" state, not a code fault.
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


async def test_status_reflects_completed_run(
    worker_client: AsyncClient,
    db_pool: DirectDatabasePool,
    gym_id: UUID,
) -> None:
    """A completed run drives last_updated + last_run_status; running is False,
    and the response carries no 'queued' field (there is no queue)."""
    async with db_pool.session() as session, session.begin():
        run_id = (
            await session.execute(
                text(
                    "INSERT INTO video_run (gym_id, status, finished_at) "
                    "VALUES (:g, 'completed', now()) RETURNING run_id"
                ),
                {"g": str(gym_id)},
            )
        ).scalar_one()
    try:
        resp = await worker_client.get(
            f"/api/v1/gyms/{gym_id}/video-worker/status", headers=_AUTH_HEADERS
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["last_updated"] is not None
        assert body["running"] is False
        assert body["last_run_status"] == "completed"
        assert "queued" not in body
    finally:
        async with db_pool.session() as session, session.begin():
            await session.execute(
                text("DELETE FROM video_run WHERE run_id = :r"),
                {"r": str(run_id)},
            )


async def test_status_no_runs_returns_none_last_updated(
    worker_client: AsyncClient,
) -> None:
    """A gym with no runs → empty status (and no 'queued' field)."""
    fresh_gym = uuid4()
    resp = await worker_client.get(
        f"/api/v1/gyms/{fresh_gym}/video-worker/status", headers=_AUTH_HEADERS
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["last_updated"] is None
    assert body["running"] is False
    assert body["last_run_status"] is None
    assert "queued" not in body
