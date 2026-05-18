"""LiteLLMImageGenerator — image generation via litellm, provider-agnostic.

The mirror of ``LiteLLMClient`` for images: it does not know or care which
provider it is talking to. The model id is passed in per call, carries the
provider prefix litellm routes on, and ``provider_keys`` resolves that
provider's key — so switching image providers/models is a one-constant
change in the calling module, never a new class here.

(``BflImageGenerator`` existed only because litellm's BFL image path is
broken upstream; that does not apply to OpenAI/gpt-image, so this goes
straight through ``litellm.aimage_generation``.)
"""

from __future__ import annotations

import base64
import logging
from pathlib import Path
from typing import Any

import litellm

from src.core.errors import ProviderError
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.services.provider_keys import provider_api_key
from schema import AbsolutePath

logger = logging.getLogger(__name__)

# Generic litellm image-call params. The model id is NOT here — it is a
# per-call constant in the module that makes the call.
IMAGE_SIZE = "1024x1024"
OUTPUT_FORMAT = "png"


def _b64_payload(item: Any) -> str:
    """Pull the base64 PNG off a litellm image-data item (attr or mapping)."""
    try:
        return item["b64_json"]
    except (TypeError, KeyError):
        return item.b64_json


class LiteLLMImageGenerator(ImageGenerator):
    """Concrete image generator that calls any litellm image model."""

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        """Generate an image for the prompt and write the PNG to ``dest``.

        Raises:
            ProviderError: the generation call or its payload failed.
        """
        logger.debug(
            "image generation input → %s (quality=%s):\n\n%s\n",
            model,
            quality,
            prompt,
        )
        try:
            resp = await litellm.aimage_generation(
                model=model,
                prompt=prompt,
                quality=quality,
                size=IMAGE_SIZE,
                n=1,
                output_format=OUTPUT_FORMAT,
                api_key=provider_api_key(model),
            )
            image_bytes = base64.b64decode(_b64_payload(resp.data[0]))
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(image_bytes)
        except ProviderError:
            raise
        except Exception as exc:
            raise ProviderError(
                f"image generation failed for model {model!r}: {exc}"
            ) from exc

        return AbsolutePath(str(dest.resolve()))
