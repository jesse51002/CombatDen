"""Smoke tests for the live FastAPI backend integration harness.

These tests verify that:
- The backend is reachable and healthy.
- The seeded gym owner can authenticate and reach the gyms list endpoint.
- The conftest fixtures (auth_token, api, gym_id) are wired correctly.

Run with the server already up:
    poetry run pytest tests/integration/test_smoke_integration.py -v
"""

import httpx


def test_health(api: httpx.Client) -> None:
    """GET /health returns 200."""
    response = api.get("/health")
    assert response.status_code == 200


def test_gyms_list_returns_seeded_gym(
    api: httpx.Client, gym_id: str
) -> None:
    """GET /api/v1/gyms/ returns 200 and includes the seeded gym."""
    response = api.get("/api/v1/gyms/")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list), f"expected a list, got: {data}"
    ids = [str(g.get("gym_id")) for g in data]
    # gym_id fixture must appear among the caller's administered gyms.
    assert gym_id in ids, f"seeded gym {gym_id} not in {ids}"
