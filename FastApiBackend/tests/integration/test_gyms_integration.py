"""Integration tests for the gyms domain.

Covers:
    GET  /api/v1/gyms/                       — list the caller's gyms
    GET  /api/v1/gyms/{gym_id}/onboarding    — Stripe onboarding status
                                               refresh (owner only)

Read-only.  No POST /api/v1/gyms/ (would hit Stripe + pollute seed).

Run with the live server already up:
    poetry run pytest tests/integration/test_gyms_integration.py -v
"""

import uuid

import httpx
import pytest

# ── Helpers ───────────────────────────────────────────────────────────────────

_KNOWN_STATUSES = {"not_started", "pending", "complete"}
_ADMIN_ROLES = {"owner", "admin"}


# ── GET /api/v1/gyms/ ─────────────────────────────────────────────────────────


class TestListMyGyms:
    """Tests for GET /api/v1/gyms/ (list of gyms the caller administers)."""

    def test_returns_200(self, api: httpx.Client) -> None:
        """Endpoint is reachable and returns HTTP 200."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text

    def test_returns_a_list(self, api: httpx.Client) -> None:
        """Response body is a JSON array."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        assert isinstance(response.json(), list)

    def test_items_have_required_fields(self, api: httpx.Client) -> None:
        """Each gym carries the GymWithRoleResponse fields incl. employee_type."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        data = response.json()
        assert data, "Seeded owner should administer at least one gym"
        for gym in data:
            for field in ("gym_id", "gym_name", "timezone", "employee_type"):
                assert field in gym, f"Required field '{field}' missing: {gym}"

    def test_seeded_gym_is_present(self, api: httpx.Client, gym_id: str) -> None:
        """The owner's seeded gym appears in the list with an admin role."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        data = response.json()
        by_id = {gym["gym_id"]: gym for gym in data}
        assert gym_id in by_id
        assert by_id[gym_id]["employee_type"] in _ADMIN_ROLES

    def test_only_owner_or_admin_roles(self, api: httpx.Client) -> None:
        """The list never includes a trainer-only membership."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        for gym in response.json():
            assert gym["employee_type"] in _ADMIN_ROLES, (
                f"Unexpected role in admin gym list: {gym['employee_type']}"
            )

    def test_gym_id_is_valid_uuid(self, api: httpx.Client) -> None:
        """Each gym_id parses as a valid UUID."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        for gym in response.json():
            parsed = uuid.UUID(str(gym["gym_id"]))
            assert str(parsed) == str(gym["gym_id"])

    def test_no_extra_stripe_fields_leaked(self, api: httpx.Client) -> None:
        """The list must NOT expose Stripe fields (stripe_account_id etc.)."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        forbidden_fields = {
            "stripe_account_id",
            "stripe_onboarding_status",
            "onboarding_url",
        }
        for gym in response.json():
            leaked = forbidden_fields & set(gym.keys())
            assert not leaked, f"Stripe fields leaked into gym list: {leaked}"

    def test_unauthenticated_returns_401_or_403(self) -> None:
        """GET /api/v1/gyms/ without auth returns 401 or 403."""
        client = httpx.Client(base_url="http://localhost:8000", timeout=10.0)
        response = client.get("/api/v1/gyms/")
        client.close()
        assert response.status_code in (401, 403), (
            f"Expected 401 or 403 for unauthenticated request, got {response.status_code}"
        )

    def test_response_content_type_is_json(self, api: httpx.Client) -> None:
        """Response has application/json content-type."""
        response = api.get("/api/v1/gyms/")
        assert response.status_code == 200, response.text
        assert "application/json" in response.headers.get("content-type", "")


# ── GET /api/v1/gyms/{gym_id}/onboarding ──────────────────────────────────────


class TestGetOnboardingStatus:
    """Tests for GET /api/v1/gyms/{gym_id}/onboarding (owner only).

    This endpoint hits Stripe.  For a seeded local gym without a real
    Stripe account, we expect either:
      - 200  with a valid GymOnboardingStatusResponse, OR
      - 404  "Gym has no Stripe account ..." (no stripe_account_id), OR
      - 502  Stripe connectivity error (Stripe not reachable / configured)

    Any of those is an ACCEPTABLE outcome from a contract perspective.
    What is NOT acceptable is a 500 with an unhandled exception, or a 200
    whose body violates the declared schema.
    """

    def test_does_not_return_500(self, api: httpx.Client, gym_id: str) -> None:
        """Endpoint must not blow up with a 500."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        assert response.status_code != 500, (
            f"GET /api/v1/gyms/{gym_id}/onboarding returned 500: {response.text}"
        )

    def test_returns_acceptable_status_code(self, api: httpx.Client, gym_id: str) -> None:
        """Endpoint must return one of 200, 404, or 502 for the owner."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        assert response.status_code in (200, 404, 502), (
            f"Unexpected status {response.status_code}: {response.text}"
        )

    def test_200_response_has_required_fields(self, api: httpx.Client, gym_id: str) -> None:
        """If 200, body must contain all required response fields."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        if response.status_code != 200:
            pytest.skip(
                f"Skipping schema validation — endpoint returned {response.status_code} "
                "(Stripe not configured or no stripe_account_id for seeded gym)"
            )

        data = response.json()
        for field in (
            "gym_id",
            "stripe_onboarding_status",
            "details_submitted",
            "charges_enabled",
            "payouts_enabled",
        ):
            assert field in data, f"Required field '{field}' missing: {data}"

    def test_200_stripe_onboarding_status_enum(self, api: httpx.Client, gym_id: str) -> None:
        """If 200, stripe_onboarding_status must be a declared enum value."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        if response.status_code != 200:
            pytest.skip("Endpoint did not return 200")

        data = response.json()
        status_val = data.get("stripe_onboarding_status")
        assert status_val in _KNOWN_STATUSES, (
            f"stripe_onboarding_status '{status_val}' not in {_KNOWN_STATUSES}"
        )

    def test_200_boolean_fields(self, api: httpx.Client, gym_id: str) -> None:
        """If 200, details_submitted / charges_enabled / payouts_enabled are bools."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        if response.status_code != 200:
            pytest.skip("Endpoint did not return 200")

        data = response.json()
        for field in ("details_submitted", "charges_enabled", "payouts_enabled"):
            assert isinstance(data[field], bool), (
                f"'{field}' should be bool, got {type(data[field])}: {data[field]}"
            )

    def test_200_gym_id_matches_fixture(self, api: httpx.Client, gym_id: str) -> None:
        """If 200, gym_id in the response matches the requested gym."""
        response = api.get(f"/api/v1/gyms/{gym_id}/onboarding")
        if response.status_code != 200:
            pytest.skip("Endpoint did not return 200")

        data = response.json()
        assert str(data["gym_id"]) == gym_id

    def test_non_owned_gym_returns_403(self, api: httpx.Client) -> None:
        """A gym the caller does not own is rejected with 403 (owner only)."""
        random_id = str(uuid.uuid4())
        response = api.get(f"/api/v1/gyms/{random_id}/onboarding")
        assert response.status_code == 403, (
            f"Expected 403 for a non-owned gym, got {response.status_code}: {response.text}"
        )

    def test_unauthenticated_returns_401_or_403(self, gym_id: str) -> None:
        """Unauthenticated request returns 401 or 403."""
        client = httpx.Client(base_url="http://localhost:8000", timeout=10.0)
        response = client.get(f"/api/v1/gyms/{gym_id}/onboarding")
        client.close()
        assert response.status_code in (401, 403), (
            f"Expected 401/403 for unauthenticated request, got {response.status_code}"
        )
