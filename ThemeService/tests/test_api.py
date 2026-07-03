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

from src.api.config import Settings, settings
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

    Also pins ``assets_cdn_base_url`` to empty so this suite exercises the
    LOCAL serving path (relative URLs + on-disk bytes) by default. The
    setting now defaults to the prod CDN (see ``test_cdn_*``), so the local
    path has to be selected explicitly; tests that want the CDN behaviour
    re-set this within the test.
    """
    monkeypatch.setattr(settings, "apps_root", FIXTURE_APPS)
    monkeypatch.setattr(settings, "assets_cdn_base_url", "")
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
    # The slot's content fingerprint rides along as a cache-busting ?v= token.
    assert body["images"] == {
        "hero": f"/apps/{APP}/run1/images/hero?v=testhash1234"
    }

    # Fonts collapse to a flat slot -> Google Fonts family map.
    assert body["fonts"] == {
        slot_id: font["family"]
        for slot_id, font in expected["font_set"]["fonts"].items()
    }

    # The text group passes through unchanged; run1 declares none, so it
    # is the empty default.
    assert body["text_set"] == {"texts": {}}


def test_image_url_carries_version_token() -> None:
    """Every image slot is versioned (the field is required), so its served URL
    carries the content-hash ``?v=`` cache-bust token."""
    body = client.get(f"/apps/{APP}/default").json()
    assert (
        body["images"]["hero"]
        == f"/apps/{APP}/default/images/hero?v=0123456789ab"
    )


def test_image_served_from_final_images() -> None:
    resp = client.get(f"/apps/{APP}/run1/images/hero")
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    # One-day freshness so owner asset swaps propagate within ~24h.
    assert resp.headers["cache-control"] == "max-age=86400"
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
    ``hero`` slot (no ``celebration_image``), so the page is empty —
    but it is a 200 envelope, proving the route ordering."""
    resp = client.get(f"/apps/{APP}/styles")
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"items": [], "total": 0, "offset": 0, "limit": 20}


def test_styles_unknown_app_404() -> None:
    assert client.get("/apps/no_such_app/styles").status_code == 404


def test_list_styles_excludes_date_runs_and_imageless(tmp_path: Path) -> None:
    """A named style with a ``celebration_image`` PNG lists; a
    date-stamped run is skipped even if it has the image; a named dir
    without the image is skipped.

    The copied ``default/output.yaml`` already carries ``category:
    Modern`` and no ``app.yaml`` is seeded into ``tmp_path/demo``, so
    the vocabulary check is skipped (no declared categories) — only the
    date-stamp / missing-image filters are under test here."""
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
    page = asyncio.run(svc.list_styles("demo"))

    assert page.total == 1
    assert page.offset == 0
    assert page.limit == 20
    assert [s.id for s in page.items] == ["ZenStyle"]
    assert page.items[0].display_name == "Demo App"
    # The celebration URL carries the image's content-hash `?v=` token (hashed
    # on the spot here, since this fixture's output.yaml declares no version),
    # so a regenerated card busts its cache instead of sitting on the old copy.
    assert page.items[0].celebration_image.startswith(
        "/apps/demo/ZenStyle/images/celebration_image?v="
    )


def _seed_named_styles(
    apps_root: Path,
    names: list[str],
    *,
    category: str | None = "Modern",
) -> None:
    """Stamp out ``apps_root/demo/<name>/`` style dirs with the demo
    output.yaml + a celebration_image PNG so ``list_styles`` picks
    them up.

    ``category`` (default ``"Modern"``, matching the demo app's
    declared vocabulary — see ``tests/data/apps/demo/app.yaml``) is
    stamped into each seeded run's ``output.yaml``, overriding whatever
    the template carries. Pass a value outside the declared vocabulary
    to simulate a stale/mismatched category, or ``None`` to simulate a
    run with no category at all (both are skipped by the styles-list
    category filter — see the dedicated tests below)."""
    src_output = yaml.safe_load(
        (FIXTURE_APPS / APP / "default" / "output.yaml").read_text()
    )
    appdir = apps_root / "demo"
    for name in names:
        d = appdir / name / "final_images"
        d.mkdir(parents=True)
        run_output = dict(src_output)
        if category is None:
            run_output.pop("category", None)
        else:
            run_output["category"] = category
        (appdir / name / "output.yaml").write_text(yaml.safe_dump(run_output))
        (d / "celebration_image.png").write_bytes(b"png")


def _write_demo_app_yaml(
    apps_root: Path, categories: list[str] | None
) -> None:
    """Write ``apps_root/demo/app.yaml`` declaring a classification
    vocabulary, based on the committed fixture ``app.yaml``.

    ``categories=None`` omits the ``categories`` key entirely — the
    "app declares no classification concept" case, which skips the
    vocabulary check (any non-null run category is accepted). Pass a
    list (even empty) to declare an explicit closed vocabulary."""
    app_format = yaml.safe_load((FIXTURE_APPS / APP / "app.yaml").read_text())
    if categories is None:
        app_format.pop("categories", None)
    else:
        app_format["categories"] = categories
    (apps_root / "demo").mkdir(parents=True, exist_ok=True)
    (apps_root / "demo" / "app.yaml").write_text(yaml.safe_dump(app_format))


def test_list_styles_paginates(tmp_path: Path) -> None:
    """``offset``/``limit`` slice the post-sort list and the envelope
    echoes both back with the unsliced total."""
    _seed_named_styles(
        tmp_path,
        ["AAA", "BBB", "CCC", "DDD", "EEE"],
    )
    # `display_name` is `Demo App` for every fixture, so the sort
    # collapses to the input order (stable) — the ids in `items` are
    # the alphabetic dir order: AAA, BBB, CCC, DDD, EEE.
    svc = OutputService(apps_root=tmp_path)
    page = asyncio.run(svc.list_styles("demo", offset=1, limit=2))

    assert page.total == 5
    assert page.offset == 1
    assert page.limit == 2
    assert [s.id for s in page.items] == ["BBB", "CCC"]


def test_list_styles_search_is_substring_case_insensitive(
    tmp_path: Path,
) -> None:
    """``query`` matches a substring of the id (case-insensitive); the
    total reflects the post-filter count, not the catalog size."""
    _seed_named_styles(tmp_path, ["ZenStyle", "ApexMMA", "ZenBoxing"])
    svc = OutputService(apps_root=tmp_path)
    page = asyncio.run(svc.list_styles("demo", query="zen"))

    assert page.total == 2
    assert sorted(s.id for s in page.items) == ["ZenBoxing", "ZenStyle"]


def test_list_styles_caches_full_list_between_calls(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A second call (different page / different query) reuses the cached
    full list and does not re-load every output.yaml from disk."""
    _seed_named_styles(tmp_path, ["AAA", "BBB", "CCC"])
    svc = OutputService(apps_root=tmp_path)

    load_calls = 0
    real_load = svc.load

    async def counting_load(app_id: str, run_id: str):
        nonlocal load_calls
        load_calls += 1
        return await real_load(app_id, run_id)

    monkeypatch.setattr(svc, "load", counting_load)

    asyncio.run(svc.list_styles("demo", offset=0, limit=1))
    first_call_loads = load_calls
    assert first_call_loads == 3  # one load per surviving dir

    asyncio.run(svc.list_styles("demo", offset=1, limit=1, query="b"))
    # Second call hits the cache, so no further `load()` happens.
    assert load_calls == first_call_loads


def test_list_styles_cache_invalidates_when_a_new_style_lands(
    tmp_path: Path,
) -> None:
    """Adding a new run dir bumps the apps/<app>/ mtime, so the next
    list_styles call rebuilds and includes the newcomer."""
    _seed_named_styles(tmp_path, ["AAA", "BBB"])
    svc = OutputService(apps_root=tmp_path)

    first = asyncio.run(svc.list_styles("demo"))
    assert [s.id for s in first.items] == ["AAA", "BBB"]

    _seed_named_styles(tmp_path, ["CCC"])
    second = asyncio.run(svc.list_styles("demo"))
    assert [s.id for s in second.items] == ["AAA", "BBB", "CCC"]

    # Undeclared slot: 404 with a message distinct from "incomplete run".
    resp = client.get(f"/apps/{APP}/run1/images/no_such_slot")
    assert resp.status_code == 404
    assert "not declared" in resp.json()["detail"]


def test_list_styles_returns_category_on_the_wire(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Each style in the JSON response carries its ``category`` field —
    exercised through the real HTTP endpoint, not just the internal
    ``StyleSummary`` model."""
    _write_demo_app_yaml(tmp_path, ["Modern", "Classic"])
    _seed_named_styles(tmp_path, ["ZenStyle"], category="Modern")

    monkeypatch.setattr(settings, "apps_root", tmp_path)
    monkeypatch.setattr(
        output_service, "_DEFAULT", OutputService(apps_root=tmp_path)
    )

    resp = client.get(f"/apps/{APP}/styles")
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert len(items) == 1
    assert items[0]["category"] == "Modern"


def test_list_styles_skips_run_without_category(tmp_path: Path) -> None:
    """A named run whose ``output.yaml`` carries no ``category`` at
    all is skipped — category is required on the wire, so an
    uncategorised run is never listed."""
    _seed_named_styles(tmp_path, ["Categorized"], category="Modern")
    _seed_named_styles(tmp_path, ["Uncategorized"], category=None)

    svc = OutputService(apps_root=tmp_path)
    page = asyncio.run(svc.list_styles("demo"))

    assert [s.id for s in page.items] == ["Categorized"]


def test_list_styles_skips_category_outside_declared_vocabulary(
    tmp_path: Path,
) -> None:
    """When the app declares a closed vocabulary, a run whose
    (non-null) category isn't one of the declared values is skipped,
    even though a category is present."""
    _write_demo_app_yaml(tmp_path, ["Modern", "Classic"])
    _seed_named_styles(tmp_path, ["InVocab"], category="Modern")
    _seed_named_styles(tmp_path, ["OutOfVocab"], category="Retro")

    svc = OutputService(apps_root=tmp_path)
    page = asyncio.run(svc.list_styles("demo"))

    assert [s.id for s in page.items] == ["InVocab"]


def test_list_styles_lists_categorised_runs_when_app_declares_no_vocabulary(
    tmp_path: Path,
) -> None:
    """An app whose ``app.yaml`` declares no ``categories`` at all
    (the default for apps with no classification concept) skips the
    vocabulary check entirely — any non-null category is accepted."""
    _write_demo_app_yaml(tmp_path, None)
    _seed_named_styles(tmp_path, ["AnyCategory"], category="Whatever")

    svc = OutputService(apps_root=tmp_path)
    page = asyncio.run(svc.list_styles("demo"))

    assert [s.id for s in page.items] == ["AnyCategory"]


def test_cdn_base_url_defaults_to_prod_cdn() -> None:
    """The setting defaults to the prod CDN, so the de-baked container emits
    absolute CDN URLs even when the App Runner env var is never set — a
    relative path would 404 since the image bytes aren't baked in anymore."""
    assert (
        Settings.model_fields["assets_cdn_base_url"].default
        == "https://cdn.combatden.net"
    )


def test_get_output_emits_absolute_cdn_urls_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """With a CDN base set, image URLs become absolute ``cdn/themes/...`` links
    keyed by app/run/slot, carrying the same ``?v=`` content fingerprint."""
    monkeypatch.setattr(settings, "assets_cdn_base_url", "https://cdn.test")
    body = client.get(f"/apps/{APP}/run1").json()
    assert body["images"] == {
        "hero": "https://cdn.test/themes/demo/run1/images/hero.png?v=testhash1234"
    }


def test_image_endpoint_redirects_to_cdn_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The legacy byte endpoint 307-redirects to the CDN object when a CDN is
    configured (it doesn't even touch disk — the bytes live on S3)."""
    monkeypatch.setattr(settings, "assets_cdn_base_url", "https://cdn.test")
    resp = client.get(
        f"/apps/{APP}/run1/images/hero", follow_redirects=False
    )
    assert resp.status_code == 307
    assert (
        resp.headers["location"]
        == "https://cdn.test/themes/demo/run1/images/hero.png"
    )


def test_icon_endpoint_redirects_to_cdn_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Same CDN redirect for the icon byte endpoint."""
    monkeypatch.setattr(settings, "assets_cdn_base_url", "https://cdn.test")
    resp = client.get(
        f"/apps/{APP}/run1/icons/some_icon", follow_redirects=False
    )
    assert resp.status_code == 307
    assert (
        resp.headers["location"]
        == "https://cdn.test/themes/demo/run1/icons/some_icon.svg"
    )


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