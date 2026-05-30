"""HttpxGoogleFontsCatalog — concrete catalog backed by the Google Fonts
Developer API and an in-memory TTL cache.

One process-scoped instance is enough: Google's catalog gains / loses
families slowly, so a 24h TTL is generous, and a single shared instance
across the pipeline run (and across API requests within one server
process) is cheap. The lazy load is serialised by an ``asyncio.Lock``
so concurrent callers don't issue duplicate HTTP fetches on cold start
or expiry.
"""

from __future__ import annotations

import asyncio
import logging
import time

import httpx

from src.core.errors import ProviderError
from src.shared.interfaces.google_fonts_catalog import (
    GoogleFontMetadata,
    GoogleFontsCatalog,
)

logger = logging.getLogger(__name__)


class HttpxGoogleFontsCatalog(GoogleFontsCatalog):
    """Google Fonts catalog backed by ``httpx`` with an in-memory TTL cache.

    The cache key is the lowercased family name, so lookups by any
    capitalisation hit (the LLM rarely nails Google's exact form). The
    full metadata is stored so callers can also retrieve the canonical
    capitalisation, category, and per-variant font-file URLs (the
    Developer API serves TTF; the CSS2 endpoint serves woff2 to
    browsers under a separate URL).

    Constructor args carry the Google Fonts Developer API URL, the
    fetch timeout, and the cache TTL — all of which live in Settings
    so they're env-tunable without touching this file.
    """

    def __init__(
        self,
        api_key: str,
        *,
        api_url: str,
        ttl_seconds: int,
        request_timeout_seconds: float,
    ) -> None:
        self._api_key = api_key
        self._api_url = api_url
        self._ttl_seconds = ttl_seconds
        self._request_timeout_seconds = request_timeout_seconds
        # Lowercased family -> metadata. Empty until first load.
        self._by_family: dict[str, GoogleFontMetadata] = {}
        # ``time.monotonic()`` seconds at the last successful load.
        # ``None`` means "never loaded".
        self._loaded_at: float | None = None
        # One-flight lock around the HTTP fetch so concurrent callers
        # (every font module on cold start) don't all hit Google.
        self._lock = asyncio.Lock()

    async def contains(self, family: str) -> bool:
        await self._ensure_fresh()
        return family.lower() in self._by_family

    async def lookup(self, family: str) -> GoogleFontMetadata | None:
        await self._ensure_fresh()
        return self._by_family.get(family.lower())

    async def families(self) -> frozenset[str]:
        await self._ensure_fresh()
        return frozenset(self._by_family.keys())

    async def _ensure_fresh(self) -> None:
        """Load the catalog if empty or TTL-expired."""
        if self._loaded_at is not None and (
            time.monotonic() - self._loaded_at < self._ttl_seconds
        ):
            return
        async with self._lock:
            # Re-check inside the lock — a concurrent waiter may have
            # already refreshed by the time we acquired it.
            if self._loaded_at is not None and (
                time.monotonic() - self._loaded_at < self._ttl_seconds
            ):
                return
            await self._reload()

    async def _reload(self) -> None:
        """Fetch the full catalog and replace the in-memory map.

        Raises:
            ProviderError: the transport, timeout, or response failed.
        """
        try:
            async with httpx.AsyncClient(
                timeout=self._request_timeout_seconds
            ) as client:
                resp = await client.get(
                    self._api_url,
                    params={"key": self._api_key},
                )
                resp.raise_for_status()
                payload = resp.json()
        except Exception as exc:
            raise ProviderError(
                f"Google Fonts catalog fetch failed: {exc}"
            ) from exc

        items = payload.get("items") or []
        # ``model_validate`` per item so unknown keys are dropped
        # (extra="ignore") and a malformed entry surfaces with a clear
        # field path instead of a vague ``KeyError`` downstream.
        rebuilt: dict[str, GoogleFontMetadata] = {}
        for raw in items:
            entry = GoogleFontMetadata.model_validate(raw)
            rebuilt[entry.family.lower()] = entry

        self._by_family = rebuilt
        self._loaded_at = time.monotonic()
        logger.debug(
            "Google Fonts catalog loaded: %d families", len(rebuilt)
        )
