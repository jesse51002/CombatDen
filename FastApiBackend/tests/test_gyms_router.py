"""Smoke + edge tests for the gyms router."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from fastapi import HTTPException, status

from src.gyms.schema.gyms_schema import GymCreateResponse


def test_create_gym_returns_201_with_onboarding_url(client, auth_headers):
    """POST /api/v1/gyms/ creates the gym + Stripe account and returns onboarding."""
    gym_id = uuid4()
    mock_response = GymCreateResponse(
        gym_id=gym_id,
        stripe_account_id="acct_test123",
        stripe_onboarding_status="pending",
        onboarding_url="https://connect.stripe.com/setup/e/acct_test123",
        onboarding_url_expires_at=datetime.now(UTC) + timedelta(minutes=5),
    )

    mock_service = MagicMock()
    mock_service.create_gym = AsyncMock(return_value=mock_response)

    container = client.app.container
    container.gyms_service.override(mock_service)
    try:
        response = client.post(
            "/api/v1/gyms/",
            json={
                "gym_name": "Aztec MMA",
                "owner_first_name": "Jesse",
                "owner_last_name": "Musa",
            },
            headers=auth_headers,
        )
    finally:
        container.gyms_service.reset_override()

    assert response.status_code == 201
    body = response.json()
    assert body["gym_id"] == str(gym_id)
    assert body["stripe_account_id"] == "acct_test123"
    assert body["stripe_onboarding_status"] == "pending"
    assert body["onboarding_url"].startswith("https://")


def test_list_my_gyms_returns_empty_list(client, db_pool_mock, auth_headers):
    """GET /api/v1/gyms/ returns [] (200) when the user administers no gyms."""
    session = db_pool_mock.session.return_value
    empty = MagicMock()
    empty.mappings.return_value.fetchall.return_value = []
    session.execute = AsyncMock(return_value=empty)

    response = client.get("/api/v1/gyms/", headers=auth_headers)
    assert response.status_code == 200
    assert response.json() == []


def test_list_my_gyms_returns_role_annotated_gyms(client, db_pool_mock, auth_headers):
    """GET /api/v1/gyms/ returns each gym annotated with the caller's role."""
    gym_a = uuid4()
    gym_b = uuid4()
    rows = [
        {
            "gym_id": gym_a,
            "gym_name": "Aztec MMA",
            "gym_description": None,
            "timezone": "America/Chicago",
            "employee_type": "owner",
            "theme_preference": "dark",
        },
        {
            "gym_id": gym_b,
            "gym_name": "North BJJ",
            "gym_description": "No-gi",
            "timezone": "America/New_York",
            "employee_type": "admin",
            "theme_preference": "system",
        },
    ]
    session = db_pool_mock.session.return_value
    result = MagicMock()
    result.mappings.return_value.fetchall.return_value = rows
    session.execute = AsyncMock(return_value=result)

    response = client.get("/api/v1/gyms/", headers=auth_headers)
    assert response.status_code == 200
    body = response.json()
    assert [g["gym_id"] for g in body] == [str(gym_a), str(gym_b)]
    assert body[0]["employee_type"] == "owner"
    assert body[1]["employee_type"] == "admin"
    # The caller's saved theme rides along so the CRM can hydrate at login.
    assert body[0]["theme_preference"] == "dark"
    assert body[1]["theme_preference"] == "system"
    # GymResponse fields must not leak Stripe state.
    assert "stripe_account_id" not in body[0]


def test_onboarding_status_403_when_not_owner(client, auth_mock, auth_headers):
    """GET /{gym_id}/onboarding is owner-only — a non-owner gets 403."""
    auth_mock.verify_gym_owner = AsyncMock(
        side_effect=HTTPException(status_code=status.HTTP_403_FORBIDDEN)
    )
    response = client.get(
        f"/api/v1/gyms/{uuid4()}/onboarding",
        headers=auth_headers,
    )
    assert response.status_code == 403


def test_onboarding_link_403_when_not_owner(client, auth_mock, auth_headers):
    """POST /{gym_id}/onboarding/link is owner-only — a non-owner gets 403."""
    auth_mock.verify_gym_owner = AsyncMock(
        side_effect=HTTPException(status_code=status.HTTP_403_FORBIDDEN)
    )
    response = client.post(
        f"/api/v1/gyms/{uuid4()}/onboarding/link",
        headers=auth_headers,
    )
    assert response.status_code == 403


def test_update_gym_400_when_no_fields(client, auth_headers):
    """PUT /api/v1/gyms/{gym_id} returns 400 if `data` is empty."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}",
        json={"data": {}},
        headers=auth_headers,
    )
    assert response.status_code == 400


def test_update_gym_theme_saves_and_echoes(client, db_pool_mock, auth_headers):
    """PUT /{gym_id}/theme persists and echoes the saved design id."""
    gym_id = uuid4()
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value={"gym_id": str(gym_id), "theme_design_id": "warm-stone"},
    )

    response = client.put(
        f"/api/v1/gyms/{gym_id}/theme",
        json={"data": {"theme_design_id": "warm-stone"}},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["gym_id"] == str(gym_id)
    assert body["theme_design_id"] == "warm-stone"
    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert bound_params["theme_design_id"] == "warm-stone"
    assert bound_params["gym_id"] == str(gym_id)


def test_update_gym_theme_404_when_gym_not_found(
    client, db_pool_mock, auth_headers
):
    """PUT /{gym_id}/theme 404s when the update matches no row."""
    db_pool_mock.execute_with_retry = AsyncMock(return_value=None)

    response = client.put(
        f"/api/v1/gyms/{uuid4()}/theme",
        json={"data": {"theme_design_id": "warm-stone"}},
        headers=auth_headers,
    )
    assert response.status_code == 404


def test_update_gym_theme_422_on_empty_value(client, auth_headers):
    """An empty theme_design_id is rejected by validation (422)."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}/theme",
        json={"data": {"theme_design_id": ""}},
        headers=auth_headers,
    )
    assert response.status_code == 422


def test_update_my_theme_saves_and_echoes(
    client, db_pool_mock, auth_headers
):
    """PUT .../employees/me/theme persists and echoes the saved theme."""
    gym_id = uuid4()
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value={"gym_id": str(gym_id), "theme_preference": "dark"},
    )

    response = client.put(
        f"/api/v1/gyms/{gym_id}/employees/me/theme",
        json={"data": {"theme_preference": "dark"}},
        headers=auth_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["gym_id"] == str(gym_id)
    assert body["theme_preference"] == "dark"
    # The enum value is cast to theme_mode in SQL, bound as its string.
    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert bound_params["theme_preference"] == "dark"
    assert bound_params["gym_id"] == str(gym_id)


def test_update_my_theme_422_on_unknown_value(client, auth_headers):
    """An out-of-enum theme value is rejected by validation (422)."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}/employees/me/theme",
        json={"data": {"theme_preference": "sepia"}},
        headers=auth_headers,
    )
    assert response.status_code == 422
