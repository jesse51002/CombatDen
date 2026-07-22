"""Integration tests for the discounts domain.

Endpoints under test:
    GET  /api/v1/discounts/?gym_id=<uuid>

These tests are READ-ONLY against the live backend at http://localhost:8000.
Presets are now plain, coupon-free gym config (regular-only: preset | custom)
with a lifetime spec (a duration span XOR an explicit end_date).
The gym_discounts view is an unfiltered passthrough (no Stripe gate), so any
seeded preset is surfaced. The tests validate contract shape, auth guards, and
query-parameter validation rather than specific row data.

Prerequisites:
- ``uvicorn src.main:app --reload`` running on port 8000.
- Local Supabase stack up on port 54321 (migrated to the new discount schema).
- conftest.py provides ``api`` (authorised httpx.Client), ``auth_token``,
  and ``gym_id`` (the one seeded gym).
"""

from __future__ import annotations

import httpx

from tests.integration.conftest import BACKEND_BASE_URL

# ── Helpers ───────────────────────────────────────────────────────────────────

ENDPOINT = "/api/v1/discounts/"

# A UUID that exists in no gym — used to verify cross-gym guard.
_OTHER_GYM_ID = "00000000-0000-0000-0000-000000000001"

# DiscountType values surfaced by presets (regular-only; linked is applied-only).
_VALID_DISCOUNT_TYPES = {"preset", "custom"}

# DiscountDurationUnit values from the OpenAPI contract.
_VALID_DURATION_UNITS = {"day", "week", "month", "cycle"}

# Required fields from the DiscountResponse schema.
_REQUIRED_FIELDS = {
    "discount_id",
    "gym_id",
    "discount_name",
    "discount_type",
    "value_id",
    "value",
    "is_deleted",
    "created_at",
}


def _assert_discount_response_shape(item: dict) -> None:
    """Assert that a single discount item matches the DiscountResponse schema.

    Checks required fields, enum values, the value-exclusivity rule, and the
    lifetime spec (a duration span XOR an explicit end_date, never both).

    The value fields (percentage_off, dollar_off, duration_*) are nested inside
    the ``value`` sub-object (DiscountValue), not at the top level of the item.
    """
    for field in _REQUIRED_FIELDS:
        assert field in item, f"Required field '{field}' missing from item: {item}"

    assert item["discount_type"] in _VALID_DISCOUNT_TYPES, (
        f"discount_type '{item['discount_type']}' not in {_VALID_DISCOUNT_TYPES}"
    )

    # Value fields live inside the nested ``value`` object.
    value = item["value"]
    assert isinstance(value, dict), (
        f"'value' expected dict, got {type(value)}: {value}"
    )

    if value.get("dollar_off") is not None:
        assert isinstance(value["dollar_off"], int), (
            f"'dollar_off' expected int, got {type(value['dollar_off'])}"
        )
    if value.get("percentage_off") is not None:
        assert isinstance(value["percentage_off"], (int, float)), (
            f"'percentage_off' expected number, got {type(value['percentage_off'])}"
        )

    # Exactly one of percentage_off / dollar_off must be set.
    has_pct = value.get("percentage_off") is not None
    has_amt = value.get("dollar_off") is not None
    assert has_pct != has_amt, (
        "Exactly one of percentage_off or dollar_off must be non-null; "
        f"got percentage_off={value.get('percentage_off')}, "
        f"dollar_off={value.get('dollar_off')}"
    )

    # Lifetime: a duration span (amount + unit together) XOR an explicit
    # end_date — never both; neither = forever.
    has_amount = value.get("duration_amount") is not None
    has_unit = value.get("duration_unit") is not None
    assert has_amount == has_unit, (
        "duration_amount and duration_unit must be set together; "
        f"got duration_amount={value.get('duration_amount')}, "
        f"duration_unit={value.get('duration_unit')}"
    )
    if has_unit:
        assert value["duration_unit"] in _VALID_DURATION_UNITS, (
            f"duration_unit '{value['duration_unit']}' not in {_VALID_DURATION_UNITS}"
        )
    assert not (has_amount and value.get("end_date") is not None), (
        "lifetime is a duration span OR an explicit end_date, never both"
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
    assert isinstance(data, list), f"Expected JSON array, got {type(data).__name__}: {data}"


def test_list_discounts_items_match_schema(api: httpx.Client, gym_id: str) -> None:
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


def test_list_discounts_content_type_json(api: httpx.Client, gym_id: str) -> None:
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
        f"{BACKEND_BASE_URL}{ENDPOINT}",
        params={"gym_id": gym_id},
        timeout=30.0,
    )
    assert response.status_code == 401, (
        f"Expected 401 for unauthenticated request, got {response.status_code}: {response.text}"
    )


def test_list_discounts_invalid_token_returns_401(gym_id: str) -> None:
    """GET /api/v1/discounts/ with an invalid Bearer token returns 401."""
    response = httpx.get(
        f"{BACKEND_BASE_URL}{ENDPOINT}",
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
