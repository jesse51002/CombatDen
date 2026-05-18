"""Read-only Output API tests.

These run entirely against the committed fixture tree under
``tests/data/apps`` — never the live ``apps/`` production runs, which
churn as the pipeline/schema evolve. ``settings.apps_root`` is pointed at
the fixtures for the duration of every test.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient

from src.api.config import settings
from src.api.errors import NotFoundError
from src.api.main import app
from src.api.service.output_service import load_output

FIXTURE_APPS = Path(__file__).resolve().parent / "data" / "apps"
APP = "demo"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_fixture_apps(monkeypatch: pytest.MonkeyPatch) -> None:
    """Serve from the fixture tree, not production ``apps/``."""
    monkeypatch.setattr(settings, "apps_root", FIXTURE_APPS)


def test_health() -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_get_output_matches_the_runs_yaml() -> None:
    expected = yaml.safe_load((FIXTURE_APPS / APP / "run1" / "output.yaml").read_text())

    resp = client.get(f"/apps/{APP}/run1")
    assert resp.status_code == 200
    body = resp.json()

    assert body["app"] == expected["app"]
    assert body["display_name"] == expected["display_name"]
    # Colours pass through unchanged (oklch/display_name/description).
    assert body["colors"] == expected["colors"]

    img = body["images"]["hero"]
    assert img["url"] == f"/apps/{APP}/run1/images/hero"
    assert img["prompt"] == expected["images"]["hero"]["prompt"]
    # The unreliable server path must never leak to the client.
    assert "path" not in img


def test_image_served_from_final_images() -> None:
    resp = client.get(f"/apps/{APP}/run1/images/hero")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    expected = (FIXTURE_APPS / APP / "run1" / "final_images" / "hero.png").read_bytes()
    assert resp.content == expected


def test_images_dir_is_never_served() -> None:
    """``imagesonly`` has the PNG only in ``images/`` (intermediates).

    There is no fallback: output.yaml is valid (200), but the image
    endpoint fails loudly because nothing is in ``final_images/``.
    """
    assert client.get(f"/apps/{APP}/imagesonly").status_code == 200
    resp = client.get(f"/apps/{APP}/imagesonly/images/hero")
    assert resp.status_code == 404
    detail = resp.json()["detail"]
    assert "final_images" in detail and "incomplete" in detail


def test_non_timestamp_run_id_works() -> None:
    """Run ids need not be timestamps (e.g. ``default``)."""
    assert client.get(f"/apps/{APP}/default").status_code == 200
    assert client.get(f"/apps/{APP}/default/images/hero").status_code == 200


def test_valid_output_but_missing_image_file_is_404() -> None:
    """``noimg`` has a valid output.yaml but no PNG on disk -> clear 404."""
    assert client.get(f"/apps/{APP}/noimg").status_code == 200
    resp = client.get(f"/apps/{APP}/noimg/images/hero")
    assert resp.status_code == 404
    assert "incomplete" in resp.json()["detail"]


def test_stale_run_returns_422_with_reason() -> None:
    """A run whose output.yaml no longer matches the schema -> 422."""
    resp = client.get(f"/apps/{APP}/stale")
    assert resp.status_code == 422
    assert "does not match the current schema" in resp.json()["detail"]
    # Image endpoint hits the same stale artifact -> also 422.
    assert client.get(f"/apps/{APP}/stale/images/hero").status_code == 422


def test_unknown_app_run_and_slot_404() -> None:
    assert client.get(f"/apps/nope/run1").status_code == 404
    assert client.get(f"/apps/{APP}/no_such_run").status_code == 404

    # Undeclared slot: 404 with a message distinct from "incomplete run".
    resp = client.get(f"/apps/{APP}/run1/images/no_such_slot")
    assert resp.status_code == 404
    assert "not declared" in resp.json()["detail"]


def test_traversal_ids_are_rejected_by_the_guard(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Malformed ids never escape apps_root; they raise NotFoundError."""
    monkeypatch.setattr(settings, "apps_root", FIXTURE_APPS)
    with pytest.raises(NotFoundError):
        asyncio.run(load_output("../../etc", "run1"))
    with pytest.raises(NotFoundError):
        asyncio.run(load_output(APP, "../.."))
    # The legitimate run still resolves.
    assert asyncio.run(load_output(APP, "run1")).app == APP


def test_encoded_traversal_via_http_is_404() -> None:
    assert client.get("/apps/..%2f..%2fetc/run1").status_code == 404