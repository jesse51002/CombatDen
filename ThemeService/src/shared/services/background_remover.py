"""RecraftBackgroundRemover — BackgroundRemover via the Recraft API.

Recraft's ``removeBackground`` endpoint strips the solid background off a
raster image and returns the transparent cutout. It is the same provider
(and the same ``RECRAFT_API_KEY``) the icon module already uses for SVG
generation, so the pipeline talks to one fewer vendor.

A direct ``httpx`` client (like ``RecraftIconGenerator``), NOT litellm:
litellm has no background-removal path, and Recraft is raw HTTP. The only
Recraft-specific step is parsing the response into cutout bytes; everything
else mirrors the icon client.

Cost: litellm can't price Recraft (raw HTTP, no usage in the response), so
this holds the one flat per-call price itself
(``RECRAFT_REMOVE_BG_COST_PER_CALL``) — ``removeBackground`` takes no model
id and bills a single rate, so a flat constant fits (unlike the icon
generator's per-model price table). Update if Recraft reprices.
"""

from __future__ import annotations

import base64
import logging
from pathlib import Path

import httpx

from src.core.config import settings
from src.core.errors import ProviderError
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.services.cost import CostTracking

logger = logging.getLogger(__name__)

# Recraft authenticates with a bearer token (same key as icon generation).
AUTH_HEADER = "Authorization"

# Ask for the cutout inline as base64 rather than a result URL, so one POST
# returns the bytes (no follow-up GET that could fail on its own).
RESPONSE_FORMAT = "b64_json"

# MIME type sent for the multipart upload (we always generate PNGs).
IMAGE_MIME = "image/png"

# Flat USD per accepted removeBackground call — 10 Recraft API units, and
# 1000 units = $1 (source: recraft.ai API pricing). Recraft returns no usage
# in the response, so this is the one price the pipeline holds itself. Lives
# next to the call it prices, like the model-id constants elsewhere. Update
# if Recraft reprices.
RECRAFT_REMOVE_BG_COST_PER_CALL = 0.01

# Synthetic model-id key for the per-model cost breakdown: removeBackground
# is a flat-rate call with no model id, but it is still a paid call the
# breakdown must show, so it gets its own bucket alongside the model ids.
# Distinct from the icon generator's model-id buckets (e.g.
# "recraftv4_1_utility_vector") so the merged breakdown stays unambiguous.
RECRAFT_REMOVE_BG_MODEL_KEY = "recraft_remove_bg"

# Recraft background removal does real image work; give it generous headroom.
REQUEST_TIMEOUT_SECONDS = 120.0


class RecraftBackgroundRemover(CostTracking, BackgroundRemover):
    """Concrete background remover backed by the Recraft API.

    Accumulates a flat ``RECRAFT_REMOVE_BG_COST_PER_CALL`` per accepted call
    via ``CostTracking``; the writer reads ``cost`` for the run total."""

    async def remove(self, src: Path, dst: Path) -> None:
        """Send ``src`` to Recraft, write the transparent cutout to ``dst``.

        Raises:
            ProviderError: the transport, timeout, or response failed.
        """
        try:
            async with httpx.AsyncClient(
                timeout=REQUEST_TIMEOUT_SECONDS
            ) as client:
                resp = await client.post(
                    settings.recraft_remove_bg_api_url,
                    headers={
                        AUTH_HEADER: f"Bearer {settings.recraft_api_key}"
                    },
                    files={
                        "file": (
                            src.name,
                            src.read_bytes(),
                            IMAGE_MIME,
                        )
                    },
                    data={"response_format": RESPONSE_FORMAT},
                )
                resp.raise_for_status()
                # A 2xx means Recraft accepted and billed the call — count it
                # even if the cutout turns out unusable later.
                self._add_cost(
                    RECRAFT_REMOVE_BG_COST_PER_CALL,
                    RECRAFT_REMOVE_BG_MODEL_KEY,
                )
                cutout = self._read_cutout(resp.json())

            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(cutout)
        except Exception as exc:
            raise ProviderError(
                f"Recraft background removal failed for {src.name!r}: {exc}"
            ) from exc

    @staticmethod
    def _read_cutout(payload: dict) -> bytes:
        """Pull the cutout bytes out of one Recraft removeBackground response.

        With ``response_format=b64_json`` Recraft returns a single ``image``
        object carrying inline ``b64_json`` (not the ``data: [...]`` array the
        generations endpoint uses). This is the only Recraft-specific parsing
        step — if the response shape changes, only this method moves.
        """
        image = payload.get("image") or {}
        b64 = image.get("b64_json")
        if not b64:
            raise ValueError(
                f"no b64_json image in Recraft response: {payload!r}"
            )
        return base64.b64decode(b64)
