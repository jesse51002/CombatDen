"""Integration tests for the theme showcase endpoint.

Covers:
    GET /api/v1/gyms/{gym_id}/showcase — branded class + reward cards

Read-only. The 200 test is the load-bearing one: it forces BOTH showcase
SQL files to actually execute against the live schema, so a stale column
reference (the class-system rebuild once left this query pointing at the
retired per-day ``mon_instructor_id`` columns) fails here as a 500 instead
of only in production.

Run with the live server already up:
    poetry run pytest tests/integration/test_theme_showcase_integration.py -v
"""

import uuid

import httpx

_CLASS_CARD_FIELDS = (
    "name",
    "image_url",
    "description",
    "instructor_name",
    "instructor_bio",
    "instructor_image_url",
)
_REWARD_CARD_FIELDS = ("title", "image_url", "price_label", "points_cost")


class TestGetGymShowcase:
    """Tests for GET /api/v1/gyms/{gym_id}/showcase."""

    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        """Both showcase queries execute cleanly against the live schema."""
        response = api.get(f"/api/v1/gyms/{gym_id}/showcase")
        assert response.status_code == 200, response.text

    def test_body_shape(self, api: httpx.Client, gym_id: str) -> None:
        """The body echoes the gym_id and carries both card lists."""
        response = api.get(f"/api/v1/gyms/{gym_id}/showcase")
        assert response.status_code == 200, response.text
        data = response.json()
        assert data["gym_id"] == gym_id
        assert isinstance(data["classes"], list)
        assert isinstance(data["rewards"], list)

    def test_class_cards_carry_all_fields(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every class card exposes the full ShowcaseClassCard shape."""
        response = api.get(f"/api/v1/gyms/{gym_id}/showcase")
        assert response.status_code == 200, response.text
        for card in response.json()["classes"]:
            for field in _CLASS_CARD_FIELDS:
                assert field in card, f"'{field}' missing from {card}"
            assert card["name"], "Class card name must be non-empty"

    def test_reward_cards_carry_all_fields(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every reward card exposes the full ShowcaseRewardCard shape."""
        response = api.get(f"/api/v1/gyms/{gym_id}/showcase")
        assert response.status_code == 200, response.text
        for card in response.json()["rewards"]:
            for field in _REWARD_CARD_FIELDS:
                assert field in card, f"'{field}' missing from {card}"
            assert isinstance(card["points_cost"], int)

    def test_foreign_gym_is_403(self, api: httpx.Client) -> None:
        """A gym the caller doesn't staff is rejected by the employee gate."""
        response = api.get(f"/api/v1/gyms/{uuid.uuid4()}/showcase")
        assert response.status_code == 403, response.text
