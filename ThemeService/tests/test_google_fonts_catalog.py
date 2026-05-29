"""Unit tests for HttpxGoogleFontsCatalog: lazy load, TTL refresh, and
the contains/lookup/families snapshot used by the font module."""

from __future__ import annotations

import asyncio
import time
from typing import Any

import pytest

from src.shared.services.google_fonts_catalog import HttpxGoogleFontsCatalog


# Minimal Google Fonts API response shape — only the fields the
# pipeline actually reads, plus a couple of extras to confirm
# ``extra="ignore"`` drops them silently.
_RAW_PAYLOAD: dict[str, Any] = {
    "kind": "webfonts#webfontList",
    "items": [
        {
            "family": "Inter",
            "category": "sans-serif",
            "variants": ["regular", "700"],
            "files": {
                "regular": "https://fonts.gstatic.com/s/inter/regular.woff2",
                "700": "https://fonts.gstatic.com/s/inter/700.woff2",
            },
            # Extras the pipeline ignores.
            "subsets": ["latin"],
            "lastModified": "2026-04-01",
        },
        {
            "family": "Funnel Display",
            "category": "display",
            "variants": ["regular"],
            "files": {
                "regular": "https://fonts.gstatic.com/s/funneldisplay/regular.woff2",
            },
        },
    ],
}


class _FakeAsyncClient:
    """Stand-in for ``httpx.AsyncClient`` — records every GET, returns
    one canned payload."""

    last_url: str | None = None
    last_params: dict[str, Any] | None = None
    calls: int = 0

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        # Reset call counter on construction so individual tests start clean.
        pass

    async def __aenter__(self) -> "_FakeAsyncClient":
        return self

    async def __aexit__(self, *exc: Any) -> None:
        return None

    async def get(self, url: str, params: dict[str, Any] | None = None):
        type(self).last_url = url
        type(self).last_params = params
        type(self).calls += 1
        return _FakeResponse()


class _FakeResponse:
    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict[str, Any]:
        return _RAW_PAYLOAD


@pytest.fixture
def _httpx(monkeypatch: pytest.MonkeyPatch) -> type[_FakeAsyncClient]:
    """Swap httpx.AsyncClient inside the catalog module for the fake."""
    import src.shared.services.google_fonts_catalog as module

    # Reset class-level counters per test.
    _FakeAsyncClient.calls = 0
    _FakeAsyncClient.last_url = None
    _FakeAsyncClient.last_params = None
    monkeypatch.setattr(module.httpx, "AsyncClient", _FakeAsyncClient)
    return _FakeAsyncClient


def test_catalog_loads_lazily_on_first_call(_httpx) -> None:
    """No HTTP call happens at construction; the first contains/lookup/
    families call triggers exactly one fetch."""
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=60,
        request_timeout_seconds=30.0,
    )
    assert _httpx.calls == 0

    asyncio.run(catalog.contains("Inter"))
    assert _httpx.calls == 1
    assert _httpx.last_url.endswith("/webfonts/v1/webfonts")
    assert _httpx.last_params == {"key": "k"}


def test_catalog_caches_within_ttl(_httpx) -> None:
    """Subsequent calls within the TTL reuse the cached map and don't
    re-fetch."""
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=60,
        request_timeout_seconds=30.0,
    )
    asyncio.run(catalog.contains("Inter"))
    asyncio.run(catalog.lookup("Inter"))
    asyncio.run(catalog.families())
    assert _httpx.calls == 1


def test_catalog_refreshes_after_ttl(
    _httpx, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Once the TTL elapses, the next call refetches."""
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=10,
        request_timeout_seconds=30.0,
    )
    asyncio.run(catalog.contains("Inter"))
    assert _httpx.calls == 1

    # Jump time forward past the TTL.
    real_monotonic = time.monotonic
    base = real_monotonic()
    monkeypatch.setattr(time, "monotonic", lambda: base + 1000)
    asyncio.run(catalog.contains("Inter"))
    assert _httpx.calls == 2


def test_lookup_is_case_insensitive_and_returns_canonical_family(
    _httpx,
) -> None:
    """Lookups by any capitalisation hit; the entry's ``family`` field
    carries Google's canonical spelling."""
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=60,
        request_timeout_seconds=30.0,
    )
    entry = asyncio.run(catalog.lookup("funnel display"))
    assert entry is not None
    assert entry.family == "Funnel Display"
    assert entry.category == "display"

    # Mixed-case input resolves the same canonical entry.
    same = asyncio.run(catalog.lookup("FUNNEL DISPLAY"))
    assert same is not None and same.family == "Funnel Display"


def test_families_returns_lowercased_snapshot(_httpx) -> None:
    """The snapshot the font module hands to its sync model_validator is
    lowercased — the validator does a case-insensitive ``in`` check."""
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=60,
        request_timeout_seconds=30.0,
    )
    snapshot = asyncio.run(catalog.families())
    assert snapshot == frozenset({"inter", "funnel display"})


def test_unknown_family_is_none(_httpx) -> None:
    catalog = HttpxGoogleFontsCatalog(
        api_key="k",
        api_url="https://www.googleapis.com/webfonts/v1/webfonts",
        ttl_seconds=60,
        request_timeout_seconds=30.0,
    )
    assert asyncio.run(catalog.contains("Definitely Not A Font")) is False
    assert asyncio.run(catalog.lookup("Definitely Not A Font")) is None
