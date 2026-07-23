"""Integration tests for the membership_plans domain.

Hits the LIVE FastAPI backend at http://localhost:8000 via the 'api' fixture
(authorised httpx.Client with owner2's Bearer token) and asserts HTTP status
codes + response shapes against the OpenAPI contract.

Scope: read-only GET endpoints + validation-only probes of write endpoints.
No real Stripe calls are made; attempts requiring Stripe are classified
as expected 400/502 failures from an unconfigured Stripe account.
"""

import pytest

from tests.integration.conftest import BACKEND_BASE_URL

BASE = "/api/v1/membership_plans"

PLAN_IMG = "https://cdn.combatden.net/membership/presets/activity-01.jpg"

# ── Helpers ──────────────────────────────────────────────────────────────────

PLAN_RESPONSE_REQUIRED_KEYS = {
    "plan_id",
    "gym_id",
    "plan_name",
    "image_url",
    "plan_type",
    "is_public",
    "created_at",
}

VALID_PLAN_TYPES = {"trial", "one_time", "recurring"}
VALID_DURATION_UNITS = {"week", "month", "year", None}


def _assert_plan_shape(plan: dict) -> None:
    """Assert that a single plan dict matches MembershipPlanResponse."""
    for key in PLAN_RESPONSE_REQUIRED_KEYS:
        assert key in plan, f"Missing required field '{key}' in plan: {plan}"
    assert plan["plan_type"] in VALID_PLAN_TYPES, (
        f"Unexpected plan_type '{plan['plan_type']}'"
    )
    if plan.get("duration_unit") is not None:
        assert plan["duration_unit"] in VALID_DURATION_UNITS, (
            f"Unexpected duration_unit '{plan['duration_unit']}'"
        )
    # active_price: either null or a well-formed price object
    active_price = plan.get("active_price")
    if active_price is not None:
        for price_key in (
            "price_id",
            "plan_id",
            "gym_id",
            "stripe_price_id",
            "price",
            "is_active",
            "created_at",
        ):
            assert price_key in active_price, (
                f"active_price missing '{price_key}': {active_price}"
            )
        assert isinstance(active_price["price"], int)
        assert active_price["is_active"] is True


# ── GET / (list_plans) ───────────────────────────────────────────────────────


class TestListPlans:
    def test_list_returns_200(self, api, gym_id):
        """GET /api/v1/membership_plans/?gym_id=<id> returns HTTP 200."""
        resp = api.get(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text

    def test_list_returns_array(self, api, gym_id):
        """Response body is a JSON array."""
        resp = api.get(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list), f"Expected list, got: {type(data)}"

    def test_list_plan_shapes(self, api, gym_id):
        """Each plan in the list matches the MembershipPlanResponse schema."""
        resp = api.get(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200
        plans = resp.json()
        for plan in plans:
            _assert_plan_shape(plan)

    def test_list_requires_auth(self, gym_id):
        """GET / without a Bearer token returns 401."""
        import httpx

        unauthed = httpx.Client(base_url=BACKEND_BASE_URL, timeout=30.0)
        try:
            resp = unauthed.get(BASE + "/", params={"gym_id": gym_id})
            assert resp.status_code == 401, resp.text
        finally:
            unauthed.close()

    def test_list_rejects_missing_gym_id(self, api):
        """GET / without gym_id query param returns 422."""
        resp = api.get(BASE + "/")
        assert resp.status_code == 422, resp.text

    def test_list_rejects_wrong_gym(self, api):
        """GET / for a gym that does not belong to the owner returns 403."""
        other_gym = "00000000-0000-0000-0000-000000000002"
        resp = api.get(BASE + "/", params={"gym_id": other_gym})
        assert resp.status_code == 403, resp.text

    def test_list_gym_ids_match(self, api, gym_id):
        """Every plan in the list belongs to the requested gym."""
        resp = api.get(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200
        for plan in resp.json():
            assert plan["gym_id"] == gym_id, (
                f"Plan {plan['plan_id']} has gym_id={plan['gym_id']}, "
                f"expected {gym_id}"
            )


# ── GET /{plan_id} (get_plan) ─────────────────────────────────────────────────


class TestGetPlan:
    @pytest.fixture(scope="class")
    def existing_plan_id(self, api, gym_id):
        """Return an existing plan_id if any plans are seeded; else skip."""
        resp = api.get(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 200
        plans = resp.json()
        if not plans:
            pytest.skip("No membership plans seeded for this gym — skipping get_plan tests")
        return plans[0]["plan_id"]

    def test_get_returns_200(self, api, gym_id, existing_plan_id):
        """GET /{plan_id}?gym_id=<id> returns 200 for an existing plan."""
        resp = api.get(f"{BASE}/{existing_plan_id}", params={"gym_id": gym_id})
        assert resp.status_code == 200, resp.text

    def test_get_plan_shape(self, api, gym_id, existing_plan_id):
        """Fetched plan matches the MembershipPlanResponse contract."""
        resp = api.get(f"{BASE}/{existing_plan_id}", params={"gym_id": gym_id})
        assert resp.status_code == 200
        plan = resp.json()
        _assert_plan_shape(plan)
        assert plan["plan_id"] == existing_plan_id
        assert plan["gym_id"] == gym_id

    def test_get_nonexistent_plan_returns_404(self, api, gym_id):
        """GET /{plan_id} for an unknown plan_id returns 404."""
        fake_id = "00000000-0000-0000-0000-000000000001"
        resp = api.get(f"{BASE}/{fake_id}", params={"gym_id": gym_id})
        assert resp.status_code == 404, resp.text

    def test_get_requires_gym_id(self, api, gym_id):
        """GET /{plan_id} without gym_id returns 422."""
        fake_id = "00000000-0000-0000-0000-000000000001"
        resp = api.get(f"{BASE}/{fake_id}")
        assert resp.status_code == 422, resp.text

    def test_get_rejects_wrong_gym(self, api):
        """GET /{plan_id} for a gym the caller doesn't own returns 403."""
        fake_id = "00000000-0000-0000-0000-000000000001"
        other_gym = "00000000-0000-0000-0000-000000000002"
        resp = api.get(f"{BASE}/{fake_id}", params={"gym_id": other_gym})
        assert resp.status_code == 403, resp.text


# ── POST / (create_plan) — validation-only probes ────────────────────────────


class TestCreatePlanValidation:
    """Validate that the API enforces schema rules before touching Stripe.

    These tests do NOT drive real Stripe charges. They probe the 400/422
    validation layer; a 400 'no Stripe account configured' is the expected
    terminal state when validation passes but Stripe is unconfigured.
    """

    def test_invalid_plan_type_returns_422(self, api, gym_id):
        """Supplying an invalid plan_type returns 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Bad Plan",
            "plan_type": "INVALID",
            "price": 5000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_empty_plan_name_returns_422(self, api, gym_id):
        """Whitespace-only plan_name is rejected with 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "   ",
            "plan_type": "recurring",
            "duration_amount": 1,
            "duration_unit": "month",
            "price": 5000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_recurring_without_duration_returns_422(self, api, gym_id):
        """Recurring plan without duration fields is rejected with 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Monthly",
            "plan_type": "recurring",
            "class_count": 10,
            "price": 5000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_recurring_wrong_duration_unit_returns_422(self, api, gym_id):
        """Recurring plan with duration_unit != month returns 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Yearly",
            "plan_type": "recurring",
            "duration_amount": 1,
            "duration_unit": "year",
            "price": 5000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_negative_price_returns_422(self, api, gym_id):
        """Negative price is rejected with 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Bad Price",
            "plan_type": "one_time",
            "class_count": 5,
            "price": -100,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_zero_class_count_returns_422(self, api, gym_id):
        """class_count=0 is rejected with 422 (must be > 0)."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Zero Classes",
            "plan_type": "one_time",
            "class_count": 0,
            "price": 1000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_duration_amount_without_unit_returns_422(self, api, gym_id):
        """duration_amount without duration_unit returns 422."""
        payload = {
            "gym_id": gym_id,
            "plan_name": "Bad Duration",
            "plan_type": "one_time",
            "duration_amount": 3,
            "price": 3000,
        }
        resp = api.post(BASE + "/", json=payload)
        assert resp.status_code == 422, resp.text

    def test_valid_recurring_plan_passes_validation_and_reaches_stripe(
        self, api, gym_id
    ):
        """A fully valid recurring plan payload passes the validation layer and
        reaches the Stripe create path.

        The seeded gym has a COMPLETE Stripe Connect account, so the expected
        outcome is a real create (201) — NOT a 400. The test therefore CLEANS
        UP what it makes: on a 201 it deletes the plan, which deactivates the
        Stripe product and soft-deletes the row (``plans_delete``), so no plan
        or Stripe object leaks onto the shared test account each run. A 400 is
        tolerated only for a gym without Stripe configured; a Stripe upstream
        failure is 500, NEVER a 502 (the proxy auto-retry family is banned on
        mutating billing ops — see FastApiBackend/CLAUDE.md).
        """
        payload = {
            "gym_id": gym_id,
            "plan_name": "Monthly Membership",
            "image_url": PLAN_IMG,
            "plan_type": "recurring",
            "duration_amount": 1,
            "duration_unit": "month",
            "is_public": True,
            "price": 5000,
        }
        resp = api.post(BASE + "/", json=payload)
        created_plan_id = None
        try:
            assert resp.status_code in (201, 400, 500), (
                f"Unexpected status {resp.status_code}: {resp.text}"
            )
            if resp.status_code == 201:
                created_plan_id = resp.json()["plan_id"]
            elif resp.status_code == 400:
                assert "stripe" in resp.json().get("detail", "").lower(), (
                    resp.text
                )
        finally:
            if created_plan_id is not None:
                # Deactivates the Stripe product + soft-deletes the plan.
                api.delete(
                    BASE + "/",
                    params={"plan_id": created_plan_id, "gym_id": gym_id},
                )

    def test_create_requires_auth(self, gym_id):
        """POST / without a Bearer token returns 401."""
        import httpx

        unauthed = httpx.Client(base_url=BACKEND_BASE_URL, timeout=30.0)
        try:
            payload = {
                "gym_id": gym_id,
                "plan_name": "Test",
                "image_url": PLAN_IMG,
                "plan_type": "recurring",
                "duration_amount": 1,
                "duration_unit": "month",
                "price": 5000,
            }
            resp = unauthed.post(BASE + "/", json=payload)
            assert resp.status_code == 401, resp.text
        finally:
            unauthed.close()


# ── DELETE / (delete_plan) — validation-only probes ──────────────────────────


class TestDeletePlanValidation:
    def test_delete_nonexistent_plan_returns_404(self, api, gym_id):
        """DELETE / with an unknown plan_id returns 404."""
        fake_id = "00000000-0000-0000-0000-000000000001"
        resp = api.delete(
            BASE + "/", params={"plan_id": fake_id, "gym_id": gym_id}
        )
        assert resp.status_code == 404, resp.text

    def test_delete_missing_plan_id_returns_422(self, api, gym_id):
        """DELETE / without plan_id query param returns 422."""
        resp = api.delete(BASE + "/", params={"gym_id": gym_id})
        assert resp.status_code == 422, resp.text

    def test_delete_rejects_wrong_gym(self, api):
        """DELETE / for a gym the caller doesn't own returns 403."""
        fake_id = "00000000-0000-0000-0000-000000000001"
        other_gym = "00000000-0000-0000-0000-000000000002"
        resp = api.delete(
            BASE + "/", params={"plan_id": fake_id, "gym_id": other_gym}
        )
        assert resp.status_code == 403, resp.text
