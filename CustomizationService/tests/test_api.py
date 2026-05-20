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
from src.api.service import font_service
from src.api.service.output_service import load_output
from src.shared.interfaces.google_fonts_catalog import GoogleFontMetadata

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
    # Colour group passes through unchanged (mode + oklch/name/desc).
    assert body["color_set"] == expected["color_set"]

    img = body["image_set"]["images"]["hero"]
    assert img["url"] == f"/apps/{APP}/run1/images/hero"
    assert img["prompt"] == expected["image_set"]["images"]["hero"]["prompt"]
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


# --- Font endpoint ---------------------------------------------------------


class _StubCatalog:
    """In-memory Google Fonts catalog. The endpoint never hits Google
    in tests — this stub feeds the families the fixture's font_set
    references and lets one test simulate a retired family."""

    def __init__(
        self, entries: dict[str, GoogleFontMetadata] | None = None
    ) -> None:
        self._entries = entries if entries is not None else {
            "inter": GoogleFontMetadata(
                family="Inter",
                category="sans-serif",
                variants=["regular", "700"],
                files={
                    "regular": "https://fonts.gstatic.com/s/inter/regular.woff2",
                    "700": "https://fonts.gstatic.com/s/inter/700.woff2",
                },
            ),
            "funnel display": GoogleFontMetadata(
                family="Funnel Display",
                category="display",
                variants=["regular", "700"],
                files={
                    "regular": "https://fonts.gstatic.com/s/funneldisplay/regular.woff2",
                    "700": "https://fonts.gstatic.com/s/funneldisplay/700.woff2",
                },
            ),
        }

    async def contains(self, family: str) -> bool:
        return family.lower() in self._entries

    async def lookup(self, family: str) -> GoogleFontMetadata | None:
        return self._entries.get(family.lower())

    async def families(self) -> frozenset[str]:
        return frozenset(self._entries.keys())


@pytest.fixture
def _stub_catalog(monkeypatch: pytest.MonkeyPatch) -> _StubCatalog:
    """Swap the module-level lazy singleton for an in-memory stub so the
    font endpoint never hits the live Google Fonts API in tests."""
    catalog = _StubCatalog()
    monkeypatch.setattr(font_service, "_CATALOG", catalog)
    return catalog


def test_font_endpoint_returns_family_and_variant_urls(
    _stub_catalog: _StubCatalog,
) -> None:
    """The endpoint returns the canonical family, category, css_url,
    and per-variant font-file URLs the frontend fetches directly from
    fonts.gstatic.com (TTF from the Developer API, woff2 served via
    the CSS2 endpoint under a browser user-agent)."""
    resp = client.get(f"/apps/{APP}/run1/fonts/display")
    assert resp.status_code == 200
    body = resp.json()
    assert body["family"] == "Funnel Display"
    assert body["category"] == "display"
    assert body["css_url"].startswith("https://fonts.googleapis.com/css2")
    assert "Funnel%20Display" in body["css_url"]
    # Variants come straight from the catalog entry's files map.
    assert body["variants"]["regular"].startswith(
        "https://fonts.gstatic.com/"
    )


def test_font_endpoint_unknown_slot_404(_stub_catalog: _StubCatalog) -> None:
    resp = client.get(f"/apps/{APP}/run1/fonts/no_such_slot")
    assert resp.status_code == 404
    assert "not declared" in resp.json()["detail"]


def test_font_endpoint_malformed_slot_404(
    _stub_catalog: _StubCatalog,
) -> None:
    resp = client.get(f"/apps/{APP}/run1/fonts/Bad-Slot")
    assert resp.status_code == 404
    assert "invalid font slot id" in resp.json()["detail"]


def test_font_endpoint_family_retired_from_catalog_404(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Google occasionally retires a family. If the pipeline picked one
    that's no longer in the live catalog, the endpoint 404s clearly so
    the caller knows to re-run the pipeline."""
    empty = _StubCatalog(entries={})
    monkeypatch.setattr(font_service, "_CATALOG", empty)
    resp = client.get(f"/apps/{APP}/run1/fonts/display")
    assert resp.status_code == 404
    assert "no longer in the Google Fonts catalog" in resp.json()["detail"]