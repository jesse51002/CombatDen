"""RecraftIconGenerator — an ``ImageGenerator`` backed by the Recraft API.

Recraft generates native SVG vector art when asked for a vector style
(``style="vector_illustration"``) — real, scalable paths, not a raster
trace. That makes it the right generator for the icon module's fallback
path: when a curated set can't honestly cover a slot, we generate a
monochrome SVG icon here. It implements the same ``ImageGenerator``
contract as the raster generator — an icon generator is just an image
generator that emits SVG — so it needs no separate interface.

A direct ``httpx`` client (like ``PhotoRoomBackgroundRemover``), NOT
litellm: litellm's image path returns base64 raster and is hard-wired to
PNG sizes, whereas Recraft's vector output is SVG text behind a result
URL. The only Recraft-specific step is parsing the response into SVG
bytes; everything else mirrors the PhotoRoom client.

Cost: litellm can't price Recraft (raw HTTP), but Recraft's own response
reports the credits the call consumed (``meta.credits_used``), so the cost
is derived from that — actual usage, not a hardcoded per-call guess —
times a published per-credit USD rate (``RECRAFT_USD_PER_CREDIT``). This
mirrors how litellm prices the other calls from their reported usage; a
response that carries no usage counts ``$0`` with a warning (the same
guard ``cost.py`` uses), never a fabricated figure.
"""

from __future__ import annotations

import base64
import logging
from pathlib import Path

import httpx

from schema import AbsolutePath
from src.core.config import settings
from src.core.errors import ProviderError
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.services.cost import CostTracking

logger = logging.getLogger(__name__)

# Recraft authenticates with a bearer token.
AUTH_HEADER = "Authorization"

# The vector style that makes Recraft emit native SVG (vs a raster PNG).
VECTOR_STYLE = "vector_illustration"

# USD per Recraft API credit. Recraft's API bills in credits at a published
# rate of 1000 credits = $1 (so $0.001/credit); a vector_illustration image
# is 80 credits = $0.08, a raster 40 = $0.04 — but we never hardcode the
# per-image figure: each response reports its own ``credits_used`` and we
# multiply by this rate, so a model/price change tracks automatically.
RECRAFT_USD_PER_CREDIT = 0.001

# Where Recraft reports the credits a call consumed, on the response body.
CREDITS_USED_PATH = ("meta", "credits_used")

# Synthetic model-id key for the per-model cost breakdown: Recraft has no
# litellm model id, but it is still a paid call the breakdown must show, so
# it gets its own bucket alongside the model ids — exactly like PhotoRoom's.
# A provider name, not an app value.
RECRAFT_MODEL_KEY = "recraft"

# Recraft vector generations do real work; give them generous headroom.
REQUEST_TIMEOUT_SECONDS = 120.0


class RecraftIconGenerator(CostTracking, ImageGenerator):
    """Concrete ``ImageGenerator`` that emits SVG icons via the Recraft API.

    Accumulates cost from each call's reported ``credits_used`` (× the
    per-credit rate) via ``CostTracking``; the writer reads ``cost`` for
    the run total."""

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str | None = None
    ) -> AbsolutePath:
        """Generate one SVG via Recraft, write it to ``dest``, return its path.

        ``model`` is Recraft's own model id (sent in the request body) —
        Recraft is not litellm-routed, so it carries no provider prefix.
        ``quality`` is part of the shared ``ImageGenerator`` contract but
        unused here: Recraft vector generation has no quality tier (icon
        callers leave it ``None``).

        Raises:
            ProviderError: the transport, timeout, or response failed.
        """
        try:
            async with httpx.AsyncClient(
                timeout=REQUEST_TIMEOUT_SECONDS
            ) as client:
                resp = await client.post(
                    settings.recraft_api_url,
                    headers={
                        AUTH_HEADER: f"Bearer {settings.recraft_api_key}"
                    },
                    json={
                        "prompt": prompt,
                        "style": VECTOR_STYLE,
                        "model": model,
                    },
                )
                resp.raise_for_status()
                payload = resp.json()
                # Bill from the credits the response says the call used.
                self._add_cost(self._call_cost(payload), RECRAFT_MODEL_KEY)
                svg = await self._read_svg(client, payload)

            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(svg)
        except Exception as exc:
            raise ProviderError(
                f"Recraft icon generation failed for {dest.name!r}: {exc}"
            ) from exc
        return AbsolutePath(str(dest.resolve()))

    @staticmethod
    def _call_cost(payload: dict) -> float:
        """USD for one call from its reported ``meta.credits_used``.

        Never raises: a response that carries no usable credit count is
        ``0.0`` with a warning (so a missing figure is visible, not a
        fabricated price) — the same guard ``litellm_call_cost`` uses.
        """
        meta_key, credits_key = CREDITS_USED_PATH
        credits = (payload.get(meta_key) or {}).get(credits_key)
        if not isinstance(credits, (int, float)):
            logger.warning(
                "Recraft response carried no numeric %s.%s (%r) — counting $0",
                meta_key,
                credits_key,
                payload.get(meta_key),
            )
            return 0.0
        return float(credits) * RECRAFT_USD_PER_CREDIT

    @staticmethod
    async def _read_svg(client: httpx.AsyncClient, payload: dict) -> bytes:
        """Pull the SVG bytes out of one Recraft generation response.

        Recraft returns ``data: [{...}]`` where the entry carries either a
        result ``url`` (fetch it) or inline ``b64_json``. This is the only
        Recraft-specific parsing step — if the response shape changes,
        only this method moves.
        """
        data = payload.get("data") or []
        if not data:
            raise ValueError(f"no image data in Recraft response: {payload!r}")
        entry = data[0]
        if entry.get("b64_json"):
            return base64.b64decode(entry["b64_json"])
        url = entry.get("url")
        if not url:
            raise ValueError(
                f"Recraft response entry has neither url nor b64_json: {entry!r}"
            )
        svg_resp = await client.get(url)
        svg_resp.raise_for_status()
        return svg_resp.content
