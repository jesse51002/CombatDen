"""LiteLLMImageGenerator — image generation via litellm.

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

import asyncio
import base64
import logging
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any

import litellm

from src.core.errors import ProviderError
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.services.cost import CostTracking, litellm_call_cost
from src.shared.services.provider_keys import provider_api_key
from schema import AbsolutePath

logger = logging.getLogger(__name__)

# Generic litellm image-call params. The model id is NOT here — it is a
# per-call constant in the module that makes the call.
IMAGE_SIZE = "1024x1024"
OUTPUT_FORMAT = "png"

# Wait (seconds) before each retry of a failed image call, in order.
# Its length sets the retry count: 3 here → up to 3 retries on top of
# the first attempt (4 calls worst case) before giving up.
RETRY_BACKOFF_SECONDS = (5, 15, 30)


def _b64_payload(item: Any) -> str:
    """Pull the base64 PNG off a litellm image-data item (attr or mapping)."""
    try:
        return item["b64_json"]
    except (TypeError, KeyError):
        return item.b64_json


class LiteLLMImageGenerator(CostTracking, ImageGenerator):
    """Concrete text-to-image generation that calls any litellm image model.

    Accumulates a running cost via ``CostTracking`` — the writer reports
    it as the single ``image_generation`` bucket."""

    @staticmethod
    async def _call_with_retry(
        attempt: Callable[[], Awaitable[AbsolutePath]],
        *,
        what: str,
        model: str,
    ) -> AbsolutePath:
        """Run one image call+write, retrying transient failures on an
        increasing backoff (``RETRY_BACKOFF_SECONDS``) before wrapping the
        final failure as ``ProviderError``.

        ``attempt`` is the whole call-and-write unit and is re-invoked
        from scratch on every try, so a retry re-opens file handles and
        never reuses a spent coroutine. A ``ProviderError`` (e.g. a
        missing provider key) is a configuration fault, not transient: it
        is re-raised at once and never retried.
        """
        total = len(RETRY_BACKOFF_SECONDS) + 1
        for i in range(total):
            try:
                return await attempt()
            except ProviderError:
                raise
            except Exception as exc:
                if i == total - 1:
                    raise ProviderError(
                        f"image {what} failed for model {model!r} after "
                        f"{total} attempts: {exc}"
                    ) from exc
                wait = RETRY_BACKOFF_SECONDS[i]
                logger.warning(
                    "image %s attempt %d/%d failed for model %r (%s); "
                    "retrying in %ds",
                    what,
                    i + 1,
                    total,
                    model,
                    exc,
                    wait,
                )
                await asyncio.sleep(wait)
        raise AssertionError("unreachable: retry loop returns or raises")

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        """Generate an image for the prompt and write the PNG to ``dest``.

        Raises:
            ProviderError: the generation call or its payload failed
                every attempt (see ``_call_with_retry``).
        """
        logger.debug(
            "image generation input → %s (quality=%s):\n\n%s\n",
            model,
            quality,
            prompt,
        )

        async def _attempt() -> AbsolutePath:
            resp = await litellm.aimage_generation(
                model=model,
                prompt=prompt,
                quality=quality,
                size=IMAGE_SIZE,
                n=1,
                output_format=OUTPUT_FORMAT,
                api_key=provider_api_key(model),
            )
            self._add_cost(litellm_call_cost(resp, model), model)
            image_bytes = base64.b64decode(_b64_payload(resp.data[0]))
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(image_bytes)
            return AbsolutePath(str(dest.resolve()))

        return await self._call_with_retry(
            _attempt, what="generation", model=model
        )
