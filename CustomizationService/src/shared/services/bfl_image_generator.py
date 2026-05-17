"""BflImageGenerator — ImageGenerator via the Black Forest Labs API directly.

litellm's native BFL image path is broken upstream (its async handler calls
its own response transform with the wrong arity, on 1.83.7 and on main), so
the BFL submit→poll→fetch flow is done directly here — the same direct-client
pattern as PhotoRoomBackgroundRemover. Expected to become dead code once
litellm fixes its handler; swap orchestrator back to ProxyImageGenerator then.
"""

from __future__ import annotations

import asyncio
import logging
import time
from pathlib import Path

import httpx

from src.core.config import settings
from src.core.errors import ProviderError
from src.shared.interfaces.image_generator import ImageGenerator
from schema import AbsolutePath

logger = logging.getLogger(__name__)

# BFL authenticates with this header, not a bearer token.
API_KEY_HEADER = "x-key"

# Every gen model is reached at {base}/v1/{model} (flux-dev, flux-pro-1.1, …).
ENDPOINT_TEMPLATE = "{base}/v1/{model}"

# The pipeline always wants PNGs out.
OUTPUT_FORMAT = "png"

# BFL is submit-then-poll; timeouts per leg, plus a polling cap.
SUBMIT_TIMEOUT_SECONDS = 60.0
POLL_TIMEOUT_SECONDS = 30.0
DOWNLOAD_TIMEOUT_SECONDS = 60.0
POLL_INTERVAL_SECONDS = 1.5
MAX_POLL_SECONDS = 300.0

# Poll states. "Ready" carries result.sample; the rest never will.
READY_STATUS = "Ready"
FAILED_STATUSES = frozenset(
    {"Error", "Request Moderated", "Content Moderated", "Task not found"}
)


class BflImageGenerator(ImageGenerator):
    """Concrete image generator that talks to Black Forest Labs directly."""

    async def generate(self, prompt: str, dest: Path) -> AbsolutePath:
        """Generate an image for the prompt and write the PNG to ``dest``.

        Submits the prompt, polls the returned ``polling_url`` until the
        result is ready, then downloads the signed sample image.

        Raises:
            ProviderError: submission, polling, the result, or the fetch failed.
        """
        logger.debug(
            "image generation input → %s:\n\n%s\n",
            settings.image_model,
            prompt,
        )
        try:
            headers = {API_KEY_HEADER: settings.bfl_api_key}
            endpoint = ENDPOINT_TEMPLATE.format(
                base=settings.bfl_api_base.rstrip("/"),
                model=settings.image_model,
            )
            async with httpx.AsyncClient() as client:
                polling_url = await self._submit(
                    client, endpoint, headers, prompt
                )
                sample_url = await self._poll(client, polling_url, headers)
                image_bytes = await self._download(client, sample_url)

            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(image_bytes)
        except ProviderError:
            raise
        except Exception as exc:
            raise ProviderError(
                f"BFL image generation failed for model "
                f"{settings.image_model!r}: {exc}"
            ) from exc

        return AbsolutePath(str(dest.resolve()))

    async def _submit(
        self,
        client: httpx.AsyncClient,
        endpoint: str,
        headers: dict[str, str],
        prompt: str,
    ) -> str:
        """POST the prompt; return the ``polling_url`` BFL hands back."""
        resp = await client.post(
            endpoint,
            headers=headers,
            json={"prompt": prompt, "output_format": OUTPUT_FORMAT},
            timeout=SUBMIT_TIMEOUT_SECONDS,
        )
        resp.raise_for_status()
        body = resp.json()
        if "errors" in body:
            raise ProviderError(f"BFL rejected the request: {body['errors']}")
        polling_url = body.get("polling_url")
        if not polling_url:
            raise ProviderError("BFL response carried no polling_url")
        return polling_url

    async def _poll(
        self,
        client: httpx.AsyncClient,
        polling_url: str,
        headers: dict[str, str],
    ) -> str:
        """Poll until ``Ready``; return the signed sample image URL."""
        deadline = time.monotonic() + MAX_POLL_SECONDS
        while time.monotonic() < deadline:
            resp = await client.get(
                polling_url, headers=headers, timeout=POLL_TIMEOUT_SECONDS
            )
            resp.raise_for_status()
            body = resp.json()
            status = body.get("status")
            if status == READY_STATUS:
                sample = (body.get("result") or {}).get("sample")
                if not sample:
                    raise ProviderError(
                        "BFL reported Ready but carried no result.sample"
                    )
                return sample
            if status in FAILED_STATUSES:
                raise ProviderError(
                    f"BFL generation failed: status {status!r}"
                )
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
        raise ProviderError(
            f"BFL result not ready after {MAX_POLL_SECONDS:.0f}s"
        )

    async def _download(
        self, client: httpx.AsyncClient, sample_url: str
    ) -> bytes:
        """Fetch the signed sample URL to raw PNG bytes."""
        resp = await client.get(
            sample_url, timeout=DOWNLOAD_TIMEOUT_SECONDS
        )
        resp.raise_for_status()
        return resp.content
