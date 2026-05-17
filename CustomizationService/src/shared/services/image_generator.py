"""ProxyImageGenerator — the image contract implemented against the proxy."""

from __future__ import annotations

import base64
import logging
from pathlib import Path
from typing import Any

import httpx
import litellm

from src.core.config import settings
from src.core.errors import ProviderError
from src.shared.interfaces.image_generator import ImageGenerator
from schema import AbsolutePath

logger = logging.getLogger(__name__)

# Bound the fetch when the provider returns a URL instead of inline base64.
URL_FETCH_TIMEOUT_SECONDS = 60.0


class ProxyImageGenerator(ImageGenerator):
    """Concrete image generator that talks only to the LiteLLM Proxy."""

    async def _image_bytes(self, image_item: Any) -> bytes:
        """Decode one proxy image item to raw bytes.

        Prefers inline ``b64_json``; otherwise fetches ``url`` over HTTP.

        Raises:
            ProviderError: the item carried neither ``b64_json`` nor ``url``.
        """
        b64_data = getattr(image_item, "b64_json", None)
        if b64_data:
            return base64.b64decode(b64_data)

        url = getattr(image_item, "url", None)
        if url:
            async with httpx.AsyncClient(
                timeout=URL_FETCH_TIMEOUT_SECONDS
            ) as client:
                fetched = await client.get(url)
                fetched.raise_for_status()
                return fetched.content

        raise ProviderError(
            "proxy image response carried neither b64_json nor url"
        )

    async def generate(self, prompt: str, dest: Path) -> AbsolutePath:
        """Generate an image for the prompt and write it to ``dest``.

        Raises:
            ProviderError: image generation or the result fetch failed.
        """
        try:
            resp = await litellm.aimage_generation(
                model=f"litellm_proxy/{settings.image_model}",
                prompt=prompt,
                api_base=settings.litellm_proxy_url,
                api_key=settings.litellm_proxy_key,
            )
            image_bytes = await self._image_bytes(resp.data[0])
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(image_bytes)
        except ProviderError:
            raise
        except Exception as exc:
            raise ProviderError(
                f"proxy image generation failed for model "
                f"{settings.image_model!r}: {exc}"
            ) from exc

        return AbsolutePath(str(dest.resolve()))
