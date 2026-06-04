"""Integration tests for the discounts domain.

Endpoints under test:
    GET  /api/v1/discounts/?gym_id=<uuid>

These tests are READ-ONLY against the live backend at http://localhost:8000.
The gym_discounts view only surfaces rows where stripe_coupon_id IS NOT NULL,
so the seeded gym (owner1) returns an empty list — this is the expected result
(no Stripe-synced discounts in the local seed).  The tests therefore validate
contract shape, auth guards, and query-parameter validation rather than
exercising specific row data.

Prerequisites:
- ``uvicorn src.main:app --reload`` running on port 8000.
- Local Supabase stack up on port 54321.
- conftest.py provides ``api`` (authorised httpx.Client), ``auth_token``,
  and ``gym_id`` (= 21636369-8b52-9b4a-97b7-50923ceb3ffd, the one seeded gym).
"""

from __future__ import annotations

import httpx

# ── Helpers ───────────────────────────────────────────────────────────────────

ENDPOINT = "/api/v1/discounts/"

# A UUID that exists in no gym — used to verify cross-gym guard.
_OTHER_GYM_ID = "00000000-0000-0000-0000-000000000001"

# DiscountType values from the OpenAPI contract.
_VALID_DISCOUNT_TYPES = {"preset", "custom", "linked"}

# StripeCouponDuration values from the OpenAPI contract.
_VALID_DURATIONS = {"once", "repeating", "forever"}

# Required fields from the DiscountResponse schema.
_REQUIRED_FIELDS = {
    "discount_id",
    "gym_id",
    "discount_name",
    "discount_type",
    "duration",
    "created_at",
}


def _assert_discount_response_shape(item: dict) -> None:
    """Assert that a single discount item matches the DiscountResponse schema.

    Checks required fields, enum values, and optional-field types.
    """
    # Required fields present.
    for field in _REQUIRED_FIELDS:
        assert field in item, f"Required field '{field}' missing from item: {item}"

    # Enum validity.
    assert item["discount_type"] in _VALID_DISCOUNT_TYPES, (
        f"discount_type '{item['discount_type']}' not in {_VALID_DISCOUNT_TYPES}"
    )
    assert item["duration"] in _VALID_DURATIONS, (
        f"duration '{item['duration']}' not in {_VALID_DURATIONS}"
    )

    # Optional numeric fields: if present must be int/float, if absent must be null.
    for field in ("dollar_off", "linked_discount_num", "duration_in_months"):
        if item.get(field) is not None:
            assert isinstance(item[field], int), (
                f"'{field}' expected int, got {type(item[field])}: {item[field]}"
            )

    if item.get("percentage_off") is not None:
        assert isinstance(item["percentage_off"], (int, float)), (
            f"'percentage_off' expected number, got {type(item['percentage_off'])}"
        )

    # duration_in_months must be set iff duration == 'repeating'.
    if item["duration"] == "repeating":
        assert item.get("duration_in_months") is not None, (
            "duration_in_months must be set when duration == 'repeating'"
        )
    else:
        assert item.get("duration_in_months") is None, (
            "duration_in_months must be None when duration != 'repeating'"
        )

    # Exactly one of percentage_off / dollar_off must be set.
    has_pct = item.get("percentage_off") is not None
    has_amt = item.get("dollar_off") is not None
    assert has_pct != has_amt, (
        "Exactly one of percentage_off or dollar_off must be non-null; "
        f"got percentage_off={item.get('percentage_off')}, "
        f"dollar_off={item.get('dollar_off')}"
    )


# ── Happy-path tests ───────────────────────────────────────────────────────────


def test_list_discounts_returns_200(api: httpx.Client, gym_id: str) -> None:
    """GET /api/v1/discounts/?gym_id=... returns HTTP 200."""
    response = api.get(ENDPOINT, params={"gym_id": gym_id})
    assert response.status_code == 200, (
        f"Expected 200, got {response.status_code}: {response.text}"
    )


def test_list_discounts_returns_list(api: httpx.Client, gym_id: str) -> None:
    """GET /api/v1/discounts/ body is a JSON array (empty or populated)."""
    response = api.get(ENDPOINT, params={"gym_id": gym_id})
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list), (
        f"Expected JSON array, got {type(data).__name__}: {data}"
    )


def test_list_discounts_empty_for_seeded_gym(
    api: httpx.Client, gym_id: str
) -> None:
    """Seeded gym has no Stripe-synced preset discounts — list is empty.

    The gym_discounts view filters WHERE stripe_coupon_id IS NOT NULL, so
    any discount without a completed Stripe sync is hidden.  The local seed
    creates no gym_discounts rows, so this must be [].
    """
    response = api.get(ENDPOINT, params={"gym_id": gym_id})
    assert response.status_code == 200
    data = response.json()
    assert data == [], (
        f"Expected empty list for seeded gym, got: {data}"
    )


def test_list_discounts_items_match_schema(
    api: httpx.Client, gym_id: str
) -> None:
    """Every item in the discounts list conforms to the DiscountResponse schema.

    If the list is empty this test is vacuously true — the shape test fires
    whenever seed data or future test data adds rows.
    """
    response = api.get(ENDPOINT, params={"gym_id": gym_id})
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    for item in data:
        _assert_discount_response_shape(item)


def test_list_discounts_content_type_json(
    api: httpx.Client, gym_id: str
) -> None:
    """GET /api/v1/discounts/ responds with Content-Type: application/json."""
    response = api.get(ENDPOINT, params={"gym_id": gym_id})
    assert response.status_code == 200
    content_type = response.headers.get("content-type", "")
    assert "application/json" in content_type, (
        f"Expected application/json content-type, got: {content_type}"
    )


# ── Authentication tests ───────────────────────────────────────────────────────


def test_list_discounts_requires_auth(gym_id: str) -> None:
    """GET /api/v1/discounts/ without a Bearer token returns 401."""
    response = httpx.get(
        f"http://localhost:8000{ENDPOINT}",
        params={"gym_id": gym_id},
        timeout=30.0,
    )
    assert response.status_code == 401, (
        f"Expected 401 for unauthenticated request, got {response.status_code}: "
        f"{response.text}"
    )


def test_list_discounts_invalid_token_returns_401(gym_id: str) -> None:
    """GET /api/v1/discounts/ with an invalid Bearer token returns 401."""
    response = httpx.get(
        f"http://localhost:8000{ENDPOINT}",
        params={"gym_id": gym_id},
        headers={"Authorization": "Bearer not-a-valid-jwt"},
        timeout=30.0,
    )
    assert response.status_code == 401, (
        f"Expected 401 for invalid token, got {response.status_code}: {response.text}"
    )


# ── Authorization tests ────────────────────────────────────────────────────────


def test_list_discounts_wrong_gym_returns_403(api: httpx.Client) -> None:
    """GET /api/v1/discounts/ for a gym the owner doesn't own returns 403."""
    response = api.get(ENDPOINT, params={"gym_id": _OTHER_GYM_ID})
    assert response.status_code == 403, (
        f"Expected 403 for cross-gym access, got {response.status_code}: {response.text}"
    )


# ── Input validation tests ─────────────────────────────────────────────────────


def test_list_discounts_missing_gym_id_returns_422(api: httpx.Client) -> None:
    """GET /api/v1/discounts/ without gym_id query param returns 422."""
    response = api.get(ENDPOINT)
    assert response.status_code == 422, (
        f"Expected 422 for missing gym_id, got {response.status_code}: {response.text}"
    )


def test_list_discounts_invalid_uuid_gym_id_returns_422(
    api: httpx.Client,
) -> None:
    """GET /api/v1/discounts/ with a non-UUID gym_id returns 422."""
    response = api.get(ENDPOINT, params={"gym_id": "not-a-uuid"})
    assert response.status_code == 422, (
        f"Expected 422 for invalid UUID gym_id, got {response.status_code}: {response.text}"
    )
