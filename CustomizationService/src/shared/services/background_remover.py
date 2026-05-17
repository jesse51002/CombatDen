"""PhotoRoomBackgroundRemover — BackgroundRemover via the PhotoRoom API."""

from __future__ import annotations

import logging
from pathlib import Path

import httpx

from src.core.config import settings
from src.core.errors import ProviderError
from src.shared.interfaces.background_remover import BackgroundRemover

logger = logging.getLogger(__name__)

# PhotoRoom authenticates with this header, not a bearer token.
API_KEY_HEADER = "x-api-key"

# MIME type sent for the multipart upload (we always generate PNGs).
IMAGE_MIME = "image/png"

# PhotoRoom segment calls do real image work; give them generous headroom.
REQUEST_TIMEOUT_SECONDS = 120.0


class PhotoRoomBackgroundRemover(BackgroundRemover):
    """Concrete background remover backed by the PhotoRoom API."""

    async def remove(self, src: Path, dst: Path) -> None:
        """Send ``src`` to PhotoRoom, write the transparent cutout to ``dst``.

        Raises:
            ProviderError: the transport, timeout, or response failed.
        """
        try:
            async with httpx.AsyncClient(
                timeout=REQUEST_TIMEOUT_SECONDS
            ) as client:
                resp = await client.post(
                    settings.photoroom_api_url,
                    headers={API_KEY_HEADER: settings.photoroom_api_key},
                    files={
                        "image_file": (
                            src.name,
                            src.read_bytes(),
                            IMAGE_MIME,
                        )
                    },
                )
                resp.raise_for_status()
                cutout = resp.content

            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(cutout)
        except Exception as exc:
            raise ProviderError(
                f"PhotoRoom background removal failed for {src.name!r}: {exc}"
            ) from exc
