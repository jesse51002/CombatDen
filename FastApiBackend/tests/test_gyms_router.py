"""Smoke + edge tests for the gyms router."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from fastapi import HTTPException, status

from src.core.config import settings
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
            "sub_rank_type": "stripes",
            "employee_type": "owner",
            "theme_preference": "dark",
        },
        {
            "gym_id": gym_b,
            "gym_name": "North BJJ",
            "gym_description": "No-gi",
            "timezone": "America/New_York",
            "sub_rank_type": "div",
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


def test_update_gym_sets_logo_url(client, db_pool_mock, auth_headers):
    """PUT /api/v1/gyms/{gym_id} with logo_url persists and echoes it back."""
    gym_id = uuid4()
    logo_url = "https://cdn.combatden.net/gym/abc123.png?v=deadbeef"
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value={
            "gym_id": gym_id,
            "gym_name": "Aztec MMA",
            "gym_description": None,
            "timezone": "America/Chicago",
            "sub_rank_type": "stripes",
            "logo_url": logo_url,
            "theme_design_id": None,
        }
    )

    response = client.put(
        f"/api/v1/gyms/{gym_id}",
        json={"data": {"logo_url": logo_url}},
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["logo_url"] == logo_url
    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert bound_params["logo_url"] == logo_url


def test_update_gym_clears_logo_url_with_explicit_null(
    client, db_pool_mock, auth_headers
):
    """An explicit null for logo_url clears it back to NULL — unlike a
    reward's image, a gym logo is optional and clearable."""
    gym_id = uuid4()
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value={
            "gym_id": gym_id,
            "gym_name": "Aztec MMA",
            "gym_description": None,
            "timezone": "America/Chicago",
            "sub_rank_type": "stripes",
            "logo_url": None,
            "theme_design_id": None,
        }
    )

    response = client.put(
        f"/api/v1/gyms/{gym_id}",
        json={"data": {"logo_url": None}},
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["logo_url"] is None
    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert "logo_url" in bound_params
    assert bound_params["logo_url"] is None


def test_update_gym_sets_sub_rank_type(client, db_pool_mock, auth_headers):
    """PUT /api/v1/gyms/{gym_id} with sub_rank_type persists, echoes it, AND
    fires the member sub-index reconcile (the gyms -> ranks edge)."""
    from src.ranks import SQL_DIR  # noqa: PLC0415

    gym_id = uuid4()
    db_pool_mock.execute_with_retry = AsyncMock(
        return_value={
            "gym_id": gym_id,
            "gym_name": "Aztec MMA",
            "gym_description": None,
            "timezone": "America/Chicago",
            "sub_rank_type": "div",
            "logo_url": None,
            "theme_design_id": None,
        }
    )

    response = client.put(
        f"/api/v1/gyms/{gym_id}",
        json={"data": {"sub_rank_type": "div"}},
        headers=auth_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["sub_rank_type"] == "div"
    bound_params = db_pool_mock.execute_with_retry.call_args.args[1]
    assert bound_params["sub_rank_type"] == "div"

    # The style change reconciles members to stay leaf-valid.
    reconcile_sql = (SQL_DIR / "reconcile_member_sub_index_for_gym.sql").read_text()
    session = db_pool_mock.session.return_value
    reconcile_call = next(
        c
        for c in session.execute.await_args_list
        if c.args[0].text == reconcile_sql
    )
    assert reconcile_call.args[1]["sub_rank_type"] == "div"
    assert reconcile_call.args[1]["gym_id"] == str(gym_id)
    session.commit.assert_awaited()


def test_update_gym_explicit_null_sub_rank_type_422(
    client, db_pool_mock, auth_headers
):
    """sub_rank_type is NOT NULL: explicit null must 422 at the schema,
    same guard as gym_name / timezone."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}",
        json={"data": {"sub_rank_type": None}},
        headers=auth_headers,
    )

    assert response.status_code == 422
    db_pool_mock.execute_with_retry.assert_not_called()


def test_update_gym_explicit_null_gym_name_422(
    client, db_pool_mock, auth_headers
):
    """gym_name is NOT NULL: explicit null must 422 at the schema (it
    would otherwise reach the dynamic SET clause as a DB error / 500).
    Omit the field to leave it unchanged."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}",
        json={"data": {"gym_name": None}},
        headers=auth_headers,
    )

    assert response.status_code == 422
    db_pool_mock.execute_with_retry.assert_not_called()


def test_update_gym_explicit_null_timezone_422(
    client, db_pool_mock, auth_headers
):
    """timezone is NOT NULL: explicit null must 422 at the schema, same
    guard as gym_name (and it must never reach the tz remint hook)."""
    response = client.put(
        f"/api/v1/gyms/{uuid4()}",
        json={"data": {"timezone": None}},
        headers=auth_headers,
    )

    assert response.status_code == 422
    db_pool_mock.execute_with_retry.assert_not_called()


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


# ── GET /{gym_id}/app-links (PUBLIC) ──────────────────────────


def _app_links_session(db_pool_mock, row):
    """Wire db_pool_mock.session() to yield a single-row read of ``row``."""
    session = db_pool_mock.session.return_value
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    session.execute = AsyncMock(return_value=result)


def test_app_links_returns_gym_links_when_set(client, db_pool_mock):
    """A gym with its own white-label links gets them back verbatim.

    No auth header is sent — the endpoint is PUBLIC (opened from a QR on
    any phone), so it must resolve without a bearer token.
    """
    gym_id = uuid4()
    _app_links_session(
        db_pool_mock,
        {
            "gym_id": gym_id,
            "app_store_url": "https://apps.apple.com/app/aztec-mma",
            "play_store_url": "https://play.google.com/store/apps/details?id=com.aztec",
        },
    )

    response = client.get(f"/api/v1/gyms/{gym_id}/app-links")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["ios_url"] == "https://apps.apple.com/app/aztec-mma"
    assert body["android_url"] == (
        "https://play.google.com/store/apps/details?id=com.aztec"
    )


def test_app_links_falls_back_to_combatden_defaults_when_null(
    client, db_pool_mock
):
    """A gym with NULL links resolves to the CombatDen default listing."""
    gym_id = uuid4()
    _app_links_session(
        db_pool_mock,
        {"gym_id": gym_id, "app_store_url": None, "play_store_url": None},
    )

    response = client.get(f"/api/v1/gyms/{gym_id}/app-links")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["ios_url"] == settings.combatden_app_store_url
    assert body["android_url"] == settings.combatden_play_store_url


def test_app_links_404_when_gym_not_found(client, db_pool_mock):
    """An unknown gym_id is a 404 — never a default-filled 200 for a bad QR."""
    _app_links_session(db_pool_mock, None)

    response = client.get(f"/api/v1/gyms/{uuid4()}/app-links")
    assert response.status_code == 404, response.text
