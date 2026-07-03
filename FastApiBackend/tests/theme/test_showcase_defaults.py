"""Tests for the theme showcase-defaults surface.

Covers the bundled, category-keyed demo class/reward cards served from the repo
YAML file by ``ThemeShowcaseDefaultsService`` and the public
``GET /api/v1/theme/showcase-defaults`` route.

No database and no live backend: the service reads a static bundled YAML file,
and the route is public (no auth), so both are exercised with the in-process
TestClient / a direct service instance.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from src.theme.schema.theme_schema import ShowcaseCategory
from src.theme.service.theme_showcase_defaults_service import (
    ThemeShowcaseDefaultsService,
)
from src.videos.schema.videos_parent_gym_type import ParentGymType


def test_showcase_category_mirrors_parent_gym_type() -> None:
    """``ShowcaseCategory`` is documented (see its docstring in
    ``src/theme/schema/theme_schema.py``) as a hand-synced mirror of
    ``ParentGymType`` — the two value sets must never drift apart, or the
    theme domain's demo vocabulary silently diverges from the videos
    domain's real gym-type roll-up."""
    showcase_values = {c.value for c in ShowcaseCategory}
    parent_gym_type_values = {p.value for p in ParentGymType}

    assert showcase_values == parent_gym_type_values, (
        "ShowcaseCategory (src/theme/schema/theme_schema.py) has drifted "
        "from ParentGymType (src/videos/schema/videos_parent_gym_type.py) "
        "— these are hand-synced by the docstring on ShowcaseCategory; "
        "update ShowcaseCategory to match."
    )


async def test_service_loads_every_category_non_empty() -> None:
    """The real bundled YAML loads + validates, and every ShowcaseCategory is
    present with a non-empty class and reward list."""
    service = ThemeShowcaseDefaultsService()

    defaults = await service.load_defaults()

    assert set(defaults.categories.keys()) == set(ShowcaseCategory)
    for category in ShowcaseCategory:
        group = defaults.categories[category]
        assert group.classes, f"{category.value} has no classes"
        assert group.rewards, f"{category.value} has no rewards"
        # Card fields survive the port (name / instructor / image on a class;
        # title / points / price / image on a reward).
        first_class = group.classes[0]
        assert first_class.name
        assert first_class.image_url
        first_reward = group.rewards[0]
        assert first_reward.title
        assert first_reward.points_cost > 0


async def test_service_caches_after_first_load() -> None:
    """``load_defaults`` parses once and returns the cached instance after."""
    service = ThemeShowcaseDefaultsService()

    first = await service.load_defaults()
    second = await service.load_defaults()

    assert first is second


async def test_service_raises_valueerror_on_missing_category(
    tmp_path: Path,
) -> None:
    """A YAML file missing a required category fails loudly with a
    ValueError (service layer raises; the router logs + maps to 500)."""
    partial = tmp_path / "partial.yaml"
    partial.write_text(
        "categories:\n"
        "  Fighting:\n"
        "    classes:\n"
        '      - name: "Foundation"\n'
        "    rewards:\n"
        '      - title: "Bring a friend"\n'
        "        points_cost: 1000\n",
        encoding="utf-8",
    )
    service = ThemeShowcaseDefaultsService(defaults_file=partial)

    with pytest.raises(ValueError, match="missing category"):
        await service.load_defaults()


def test_route_returns_all_categories_public(client) -> None:
    """GET /api/v1/theme/showcase-defaults is public (no auth header) and
    returns every category with class + reward cards."""
    response = client.get("/api/v1/theme/showcase-defaults")

    assert response.status_code == 200
    body = response.json()
    categories = body["categories"]
    assert set(categories.keys()) == {c.value for c in ShowcaseCategory}
    fighting = categories[ShowcaseCategory.fighting.value]
    assert fighting["classes"][0]["name"] == "Foundation"
    assert fighting["classes"][0]["instructor_name"] == "Coach James Carter"
    assert fighting["rewards"][0]["title"] == "Bring a friend"
    assert fighting["rewards"][0]["points_cost"] == 1000
