"""Smoke test: the app starts and /health returns ok."""

from fastapi.testclient import TestClient


def test_health_returns_ok():
    """Verify app boots and /health responds with status ok."""
    from src.main import app

    with TestClient(app) as c:
        response = c.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
