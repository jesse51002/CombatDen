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
from src.api.service import font_service, output_service
from src.api.service.output_service import OutputService
from src.shared.interfaces.google_fonts_catalog import GoogleFontMetadata

FIXTURE_APPS = Path(__file__).resolve().parent / "data" / "apps"
APP = "demo"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_fixture_apps(monkeypatch: pytest.MonkeyPatch) -> None:
    """Serve from the fixture tree, not production ``apps/``.

    Patches ``settings.apps_root`` AND pins a fresh ``OutputService``
    pointed at the fixtures as the process-scoped singleton. The pin is
    required because ``OutputService`` captures ``apps_root`` at
    construction, so without it the lazily-built default would freeze
    on whatever ``settings.apps_root`` was when the first test ran.
    """
    monkeypatch.setattr(settings, "apps_root", FIXTURE_APPS)
    monkeypatch.setattr(
        output_service,
        "_DEFAULT",
        OutputService(apps_root=FIXTURE_APPS),
    )


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

    # Images collapse to a flat slot -> fetch-URL map; the unreliable
    # server ``path`` and the generation ``prompt`` never reach the client.
    assert body["images"] == {"hero": f"/apps/{APP}/run1/images/hero"}

    # Fonts collapse to a flat slot -> Google Fonts family map.
    assert body["fonts"] == {
        slot_id: font["family"]
        for slot_id, font in expected["font_set"]["fonts"].items()
    }

    # The text group passes through unchanged; run1 declares none, so it
    # is the empty default.
    assert body["text_set"] == {"texts": {}}


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


def test_styles_route_is_not_captured_as_a_run() -> None:
    """``/apps/{app}/styles`` resolves to the styles list, not the
    run endpoint with ``run_id='styles'``. The demo fixtures declare a
    ``hero`` slot (no ``celebration_image``), so the list is empty —
    but it is a 200 list, proving the route ordering."""
    resp = client.get(f"/apps/{APP}/styles")
    assert resp.status_code == 200
    assert resp.json() == []


def test_styles_unknown_app_404() -> None:
    assert client.get("/apps/no_such_app/styles").status_code == 404


def test_list_styles_excludes_date_runs_and_imageless(tmp_path: Path) -> None:
    """A named style with a ``celebration_image`` PNG lists; a
    date-stamped run is skipped even if it has the image; a named dir
    without the image is skipped."""
    src_output = (FIXTURE_APPS / APP / "default" / "output.yaml").read_text()
    appdir = tmp_path / "demo"
    for name in ("ZenStyle", "20260518T131056Z", "noimg"):
        d = appdir / name / "final_images"
        d.mkdir(parents=True)
        (appdir / name / "output.yaml").write_text(src_output)
    # Only the named dir + the date run carry the image; the date run is
    # still excluded by the stamp filter, "noimg" by the missing PNG.
    (appdir / "ZenStyle" / "final_images" / "celebration_image.png").write_bytes(b"png")
    (appdir / "20260518T131056Z" / "final_images" / "celebration_image.png").write_bytes(b"png")

    svc = OutputService(apps_root=tmp_path)
    styles = asyncio.run(svc.list_styles("demo"))

    assert [s.id for s in styles] == ["ZenStyle"]
    assert styles[0].display_name == "Demo App"
    assert (
        styles[0].celebration_image
        == "/apps/demo/ZenStyle/images/celebration_image"
    )

    # Undeclared slot: 404 with a message distinct from "incomplete run".
    resp = client.get(f"/apps/{APP}/run1/images/no_such_slot")
    assert resp.status_code == 404
    assert "not declared" in resp.json()["detail"]


def test_traversal_ids_are_rejected_by_the_guard() -> None:
    """Malformed ids never escape apps_root; they raise NotFoundError."""
    outputs = OutputService(apps_root=FIXTURE_APPS)
    with pytest.raises(NotFoundError):
        asyncio.run(outputs.load("../../etc", "run1"))
    with pytest.raises(NotFoundError):
        asyncio.run(outputs.load(APP, "../.."))
    # The legitimate run still resolves.
    assert asyncio.run(outputs.load(APP, "run1")).app == APP


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
    """Construct a FontService around an in-memory stub catalog and pin
    it as the process-scoped singleton, so the font endpoint never hits
    the live Google Fonts API in tests. The OutputService it depends
    on is the one already pinned by ``_use_fixture_apps``."""
    catalog = _StubCatalog()
    monkeypatch.setattr(
        font_service,
        "_DEFAULT",
        font_service.FontService(
            catalog=catalog,
            outputs=OutputService(apps_root=FIXTURE_APPS),
        ),
    )
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
    monkeypatch.setattr(
        font_service,
        "_DEFAULT",
        font_service.FontService(
            catalog=empty,
            outputs=OutputService(apps_root=FIXTURE_APPS),
        ),
    )
    resp = client.get(f"/apps/{APP}/run1/fonts/display")
    assert resp.status_code == 404
    assert "no longer in the Google Fonts catalog" in resp.json()["detail"]