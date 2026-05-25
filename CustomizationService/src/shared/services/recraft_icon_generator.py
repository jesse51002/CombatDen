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

Cost: litellm can't price Recraft (raw HTTP) and its generation response
doesn't reliably carry per-call usage, so the cost comes from Recraft's
published per-image price list (``RECRAFT_PRICE_USD``), keyed by the model
id of the call — the same model id that buckets the per-model cost
breakdown (not a synthetic provider key). An unknown model id counts
``$0`` with a warning (the same guard ``cost.py`` uses), never a
fabricated figure.
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

# Published Recraft per-image USD prices, keyed by the model id sent as the
# request ``model`` (which is also the per-model cost-breakdown bucket key).
# Recraft bills a flat rate per image by model + output type, and its
# generation response doesn't reliably carry per-call usage, so we price
# from this table. Source: recraft.ai/pricing (API tab); credits shown for
# reference (1000 credits = $1). Vector ids are the SVG path icons use;
# raster kept for completeness / non-icon callers. Update if Recraft reprices.
RECRAFT_PRICE_USD: dict[str, float] = {
    # Recraft V4.1
    "recraftv4_1": 0.04,  # 40 credits, raster
    "recraftv4_1_vector": 0.08,  # 80, vector
    "recraftv4_1_pro": 0.25,  # 250, raster
    "recraftv4_1_pro_vector": 0.30,  # 300, vector
    "recraftv4_1_utility": 0.04,  # 40, raster
    "recraftv4_1_utility_vector": 0.08,  # 80, vector
    "recraftv4_1_utility_pro": 0.25,  # 250, raster
    "recraftv4_1_utility_pro_vector": 0.30,  # 300, vector
    # Recraft V4
    "recraftv4": 0.04,  # 40, raster
    "recraftv4_vector": 0.08,  # 80, vector
    "recraftv4_pro": 0.25,  # 250, raster
    "recraftv4_pro_vector": 0.30,  # 300, vector
    # Recraft V3 / V2
    "recraftv3": 0.04,  # 40, raster
    "recraftv3_vector": 0.08,  # 80, vector
    "recraftv2": 0.022,  # 22, raster
    "recraftv2_vector": 0.044,  # 44, vector
}

# Recraft vector generations do real work; give them generous headroom.
REQUEST_TIMEOUT_SECONDS = 120.0


class RecraftIconGenerator(CostTracking, ImageGenerator):
    """Concrete ``ImageGenerator`` that emits SVG icons via the Recraft API.

    Accumulates cost from the published per-image price table, keyed by
    model id, via ``CostTracking``; the writer reads ``cost`` for the run
    total."""

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
                # A 2xx means Recraft accepted and billed the call — price
                # it from the published table, bucketed under the model id.
                self._add_cost(self._call_cost(model), model)
                svg = await self._read_svg(client, resp.json())

            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(svg)
        except Exception as exc:
            raise ProviderError(
                f"Recraft icon generation failed for {dest.name!r}: {exc}"
            ) from exc
        return AbsolutePath(str(dest.resolve()))

    @staticmethod
    def _call_cost(model: str) -> float:
        """Published USD price for one ``model`` image generation.

        Never raises: a model id absent from the price table counts ``0.0``
        with a warning (so a missing price is visible, not a fabricated
        one) — the same guard ``litellm_call_cost`` uses.
        """
        price = RECRAFT_PRICE_USD.get(model)
        if price is None:
            logger.warning(
                "no Recraft price for model %r — counting $0 (add it to "
                "RECRAFT_PRICE_USD)",
                model,
            )
            return 0.0
        return price

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
